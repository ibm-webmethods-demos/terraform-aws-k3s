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