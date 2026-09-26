# Required Providers
# https://opentofu.org/docs/language/providers/requirements

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

# Kubernetes Istio
# https://github.com/osinfra-io/pt-arche-kubernetes-istio

module "test" {
  source = "../../../../regional"

  artifact_registry    = "mock-docker.pkg.dev/mock-project/mock-virtual"
  cluster_prefix       = "mock"
  enable_istio_gateway = true
  gateway_dns          = var.gateway_dns

  labels = {
    "mock-key" = "mock-value"
  }

  multi_cluster_service_clusters = [
    {
      "link" = "mock-region/mock-cluster"
    }
  ]

  project                                     = var.project
  tls_self_signed_cert_cert_manager_root_cert = "mock-cert"
  tls_self_signed_cert_cert_manager_root_key  = "mock-key"
}
