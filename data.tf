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

resource "random_password" "k3s_server_token" {
  length  = 30
  special = false
}

data "aws_route53_zone" "main_zone" {
  count        = var.domain == "" ? 0 : 1
  name         = var.domain
  private_zone = false
}
