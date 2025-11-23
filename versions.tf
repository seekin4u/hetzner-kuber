terraform {
  backend "s3" {
    bucket = "maxsauce-infra"
    key    = "envs/hetzner"
    region = "us-east-1"
    use_lockfile = true
  }
}

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }

    aws = {
      source = "hashicorp/aws"
      version = "6.22.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    github = {
      source  = "integrations/github"
      version = ">= 6.1"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
provider "kubernetes" {
  config_path = "${path.module}/kubeconfig"
}
provider "helm" {
  kubernetes = {
    config_path = "${path.module}/kubeconfig"
  }
}