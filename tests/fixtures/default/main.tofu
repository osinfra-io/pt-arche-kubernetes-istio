# Required Providers
# https://opentofu.org/docs/language/providers/requirements

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

# Kubernetes Istio
# https://github.com/osinfra-io/pt-arche-kubernetes-istio

module "test" {
  source = "../../../"

  gateway_dns = var.gateway_dns

  gateway_retained_domain_sets = var.gateway_retained_domain_sets

  labels = {
    "mock-key" = "mock-value"
  }

  project = var.project
}
