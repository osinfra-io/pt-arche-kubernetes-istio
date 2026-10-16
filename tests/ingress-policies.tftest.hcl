mock_provider "google" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}

run "regional_shared_policy_references" {
  command = plan

  module {
    source = "./regional"
  }

  variables {
    cluster_prefix                              = "mock"
    enable_istio_gateway                        = true
    project                                     = "mock-project"
    tls_self_signed_cert_cert_manager_root_cert = "mock-cert"
    tls_self_signed_cert_cert_manager_root_key  = "mock-key"
  }

  assert {
    condition     = kubernetes_manifest.istio_gateway_backendconfig.manifest.spec.securityPolicy.name == "shared-ingress"
    error_message = "The Istio BackendConfig must reference the externally managed shared Cloud Armor policy."
  }

  assert {
    condition     = kubernetes_manifest.istio_gateway_frontendconfig.manifest.spec.sslPolicy == "shared-ingress"
    error_message = "The Istio FrontendConfig must reference the externally managed shared SSL policy."
  }

  assert {
    condition = (
      kubernetes_manifest.istio_gateway_backendconfig.manifest.metadata.name == "istio-gateway-backend" &&
      kubernetes_manifest.istio_gateway_backendconfig.manifest.spec.healthCheck.port == "15021" &&
      kubernetes_manifest.istio_gateway_backendconfig.manifest.spec.healthCheck.requestPath == "/healthz/ready" &&
      kubernetes_manifest.istio_gateway_backendconfig.manifest.spec.healthCheck.type == "HTTP"
    )
    error_message = "The Istio BackendConfig must retain its service-specific name and health check."
  }
}
