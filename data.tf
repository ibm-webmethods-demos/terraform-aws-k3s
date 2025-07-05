data "aws_ami" "default_ami" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "cloudinit_config" "init-master" {
  count         = var.master_node_count
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content = templatefile(
                "${path.module}/files/k3s.tpl.sh",
                {
                  instance_role    = "master"
                  instance_index   = count.index
                  k3s_server_token = random_password.k3s_server_token.result
                  k3s_version      = var.k3s_version
                  cluster_name     = var.cluster_name
                  cluster_domain   = local.cluster_domain
                  s3_bucket        = var.s3_bucket
                  node_labels      = local.master_node_labels
                  node_taints      = local.master_node_taints
                  extra_args       = "${local.custom_args} ${local.extra_api_args}"
                  kubeconfig_name  = local.s3_kubeconfig_filename
                }
              )
  }
}

data "cloudinit_config" "init-worker" {
  for_each      = local.worker_groups_map
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content = templatefile(
                "${path.module}/files/k3s.tpl.sh",
                {
                  instance_role    = "worker"
                  instance_index   = "null"
                  k3s_server_token = random_password.k3s_server_token.result
                  k3s_version      = var.k3s_version
                  cluster_name     = var.cluster_name
                  cluster_domain   = local.cluster_domain
                  node_labels      = each.value.node_labels
                  node_taints      = each.value.node_taints
                  s3_bucket        = ""
                  extra_args       = ""
                  kubeconfig_name  = ""
                }
              )
  }
}

resource "random_password" "k3s_server_token" {
  length  = 30
  special = false
}

data "aws_route53_zone" "main_zone" {
  count        = var.domain == "" ? 0 : 1
  name         = var.domain
  private_zone = false
}
