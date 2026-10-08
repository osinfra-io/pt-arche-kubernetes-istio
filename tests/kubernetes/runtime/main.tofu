# Browser authentication configuration
# https://github.com/osinfra-io/pt-pneuma

module "browser_auth" {
  source = "../../../../../pneuma/pt-pneuma/regional/istio/gateway-auth"

  extension_provider_name = "authentik"
  outpost_namespace       = "authentik"
  outpost_path_prefix     = "/outpost.goauthentik.io/auth/envoy"
  outpost_service_name    = "authentik-server"
  outpost_service_port    = 80
}

# Istio Runtime
# https://github.com/osinfra-io/pt-arche-kubernetes-istio

module "istio_runtime" {
  source = "../../../regional/runtime"

  ca_address           = null
  cluster_name         = "docker-desktop"
  cni_cpu_limits       = null
  cni_cpu_requests     = "100m"
  cni_memory_limits    = null
  cni_memory_requests  = "100Mi"
  cni_platform         = ""
  enable_ca_server     = true
  enable_multi_network = false
  environment          = "local"
  image_hub            = "docker.io/istio"
  mesh_config_extension_providers = [
    module.browser_auth.extension_provider
  ]
  mesh_config_service_settings = []
  network                      = "docker-desktop"
  pilot_autoscale_max          = 5
  pilot_autoscale_min          = 1
  pilot_cpu_limits             = "500m"
  pilot_cpu_requests           = "100m"
  pilot_memory_limits          = "512Mi"
  pilot_memory_requests        = "128Mi"
  pilot_replica_count          = 1
  proxy_cpu_limits             = "500m"
  proxy_cpu_requests           = "100m"
  proxy_memory_limits          = "256Mi"
  proxy_memory_requests        = "64Mi"
  ztunnel_cpu_limits           = "500m"
  ztunnel_cpu_requests         = "250m"
  ztunnel_memory_limits        = "512Mi"
  ztunnel_memory_requests      = "256Mi"
}
