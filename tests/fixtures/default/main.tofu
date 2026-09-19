# Required Providers
# https://opentofu.org/docs/language/providers/requirements

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    google-beta = {
      source = "hashicorp/google-beta"
    }
  }
}

# Kubernetes Istio
# https://github.com/osinfra-io/pt-arche-kubernetes-istio

module "test" {
  source = "../../../"

  cloud_armor_allow_rules = var.cloud_armor_allow_rules
  gateway_dns             = var.gateway_dns

  labels = {
    "mock-key" = "mock-value"
  }

  project = var.project
}
