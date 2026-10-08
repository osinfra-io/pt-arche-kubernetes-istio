terraform {
  backend "local" {}

  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
  }
}

provider "helm" {
  kubernetes = {
    config_context = "docker-desktop"
    config_path    = "~/.kube/config"
  }
}
