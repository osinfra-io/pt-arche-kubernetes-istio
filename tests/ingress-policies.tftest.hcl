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
    gateway_mci_ssl_certificate_names           = ["mock-certificate"]
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

  assert {
    condition = alltrue([
      !contains(keys(kubernetes_manifest.istio_east_west_gateway.manifest.spec.infrastructure.labels), "tags.datadoghq.com/source"),
      jsondecode(yamldecode(kubernetes_config_map_v1.istio_east_west_gateway_options.data.deployment).spec.template.metadata.annotations["ad.datadoghq.com/istio-proxy.logs"])[0].source == "istio",
      !contains(keys(kubernetes_manifest.istio_gateway.manifest.spec.infrastructure.labels), "tags.datadoghq.com/source"),
      jsondecode(yamldecode(kubernetes_config_map_v1.istio_gateway_options.data.deployment).spec.template.metadata.annotations["ad.datadoghq.com/istio-proxy.logs"])[0].source == "istio"
    ])
    error_message = "Both Istio gateways must use native Istio log annotations rather than a nonstandard unified source label."
  }
}
