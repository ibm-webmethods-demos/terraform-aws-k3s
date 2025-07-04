terraform {
  required_version = ">= 0.13.4"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null     = "~> 3.2"
    random   = "~> 3.4"
    cloudinit = "~> 2.3"
  }
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = "${local.cluster_domain}:6443"
  cluster_ca_certificate = local.k_config.host_cert
  client_key             = local.k_config.cert_data
  client_certificate     = local.k_config.user_crt
}

provider "helm" {
  kubernetes = {
    host                   = "${local.cluster_domain}:6443"
    cluster_ca_certificate = local.k_config.host_cert
    client_key             = local.k_config.cert_data
    client_certificate     = local.k_config.user_crt
  }
}
