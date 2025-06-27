resource "helm_release" "aws_lb_controller" {
  namespace  = "kube-system"
  name       = "aws-cloud-controller-manager"
  repository = "https://kubernetes.github.io/cloud-provider-aws"
  chart      = "aws-cloud-controller-manager"
  version    = "0.0.8"
  values = [
    file("${path.module}/values/cloud-controller.yaml")
  ]
}

resource "helm_release" "aws_lb_csi" {
  namespace  = "kube-system"
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  version    = "2.45.1"
  values = [
    file("${path.module}/values/csi.yaml")
  ]
}

resource "kubernetes_service_account" "asg_roller" {
  metadata {
    name      = "asg-roller"
    namespace = "kube-system"
    labels = {
      name = "asg-roller"
    }
  }
}

resource "kubernetes_cluster_role" "asg_roller" {
  metadata {
    name = "asg-roller"
    labels = {
      name = "asg-roller"
    }
  }
  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = ["*"]
    resources  = ["*"]
  }
  rule {
    verbs      = ["get", "list", "watch", "update", "patch"]
    api_groups = ["*"]
    resources  = ["nodes"]
  }
  rule {
    verbs      = ["get", "list", "create"]
    api_groups = ["*"]
    resources  = ["pods/eviction"]
  }
  rule {
    verbs      = ["get", "list"]
    api_groups = ["*"]
    resources  = ["pods"]
  }
}

resource "kubernetes_cluster_role_binding" "asg_roller" {
  metadata {
    name = "asg-roller"
    labels = {
      name = "asg-roller"
    }
  }
  subject {
    kind      = "ServiceAccount"
    name      = "asg-roller"
    namespace = "kube-system"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "asg-roller"
  }
}

resource "kubernetes_deployment" "aws_asg_roller" {
  metadata {
    name      = "aws-asg-roller"
    namespace = "kube-system"
    labels = {
      name = "aws-asg-roller"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "aws-asg-roller"
      }
    }

    template {
      metadata {
        labels = {
          name = "aws-asg-roller"
        }
      }

      spec {
        container {
          name  = "aws-asg-roller"
          image = "deitch/aws-asg-roller:802da75cec20116ca499cef5abd3292136a32b07"
          env {
            name  = "ROLLER_ASG"
            value = local.asg_list
          }
          env {
            name  = "ROLLER_KUBERNETES"
            value = "true"
          }
          env {
            name  = "ROLLER_VERBOSE"
            value = "true"
          }
          env {
            name  = "ROLLER_ORIGINAL_DESIRED_ON_TAG"
            value = "true"
          }
          env {
            name  = "ROLLER_DELETE_LOCAL_DATA"
            value = "true"
          }
          env {
            name  = "ROLLER_IGNORE_DAEMONSETS"
            value = "true"
          }
          env {
            name  = "AWS_REGION"
            value = var.region
          }
          image_pull_policy = "Always"
        }

        restart_policy       = "Always"
        service_account_name = "asg-roller"

        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "node-role.kubernetes.io/master"
                  operator = "In"
                  values   = ["true"]
                }
              }
            }
          }
        }

        toleration {
          key      = "node-role.kubernetes.io/master"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      }
    }
  }
}

resource "kubernetes_namespace" "nginx" {
  metadata {
    name = "nginx"
  }
}

resource "helm_release" "nginx" {
  name       = "ingress-nginx"
  chart      = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  version    = "4.12.3"
  timeout    = "1500"
  namespace  = kubernetes_namespace.nginx.id
  values = [
    file("${path.module}/values/nginx.yaml")
  ]
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  chart      = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  version    = "8.1.1"
  timeout    = "1500"
  namespace  = kubernetes_namespace.argocd.id
  values = [
    file("${path.module}/values/argocd.yaml")
  ]
}

resource "null_resource" "password" {
  provisioner "local-exec" {
    working_dir = "/tmp/argocd"
    command     = "kubectl -n argocd-staging get secret argocd-initial-admin-secret -o jsonpath={.data.password} | base64 -d > argocd-login.txt"
  }
}

resource "null_resource" "del-argo-pass" {
  depends_on = [null_resource.password]
  provisioner "local-exec" {
    command = "kubectl -n argocd-staging delete secret argocd-initial-admin-secret"
  }
}