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

data "aws_route53_zone" "cluster_domain_external_zone" {
  count        = var.cluster_domain_external == "" ? 0 : 1
  name         = var.cluster_domain_external
  private_zone = false
}

resource "random_id" "uniquename" {
  keepers = {
    # Generate a new id each time we switch to a new VPC
    vpc_id = data.aws_subnet.private_subnet[0].vpc_id
    cluster_name = var.cluster_name
  }

  byte_length = 4
}