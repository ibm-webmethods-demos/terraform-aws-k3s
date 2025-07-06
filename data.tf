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
    content = local.cloudinit_config_master[count.index]
  }
}

data "cloudinit_config" "init-worker" {
  for_each      = local.worker_groups_map
  gzip          = true
  base64_encode = true
  
  part {
    content_type = "text/x-shellscript"
    content = local.cloudinit_config_workers[each.key]
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
