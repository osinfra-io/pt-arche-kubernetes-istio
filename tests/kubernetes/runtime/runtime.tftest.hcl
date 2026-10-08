# Mocked Istio runtime profiles
# https://opentofu.org/docs/cli/commands/test/

mock_provider "helm" {}

run "cloud_wrapper_helm_parity" {
  command = apply

  module {
    source = "../../../regional/runtime"
  }

  variables {
    ca_address                      = "cert-manager-istio-csr.cert-manager.svc:443"
    chart_repository                = "https://istio-release.storage.googleapis.com/charts"
    cluster_name                    = "mock-region-a-mock-environment-nonprod"
    cni_cpu_limits                  = null
    cni_cpu_requests                = "100m"
    cni_memory_limits               = null
    cni_memory_requests             = "100Mi"
    cni_platform                    = "gke"
    enable_ca_server                = false
    enable_multi_network            = true
    environment                     = "non-production"
    image_hub                       = "mock-docker.pkg.dev/mock-project/mock-virtual/istio"
    istio_version                   = "1.31.0-rc.0"
    mesh_config_extension_providers = []
    mesh_config_service_settings    = []
    network                         = "mock-region-a-mock-environment-nonprod"
    pilot_autoscale_max             = 5
    pilot_autoscale_min             = 1
    pilot_cpu_limits                = "25m"
    pilot_cpu_requests              = "10m"
    pilot_memory_limits             = "64Mi"
    pilot_memory_requests           = "32Mi"
    pilot_replica_count             = 1
    proxy_cpu_limits                = "25m"
    proxy_cpu_requests              = "10m"
    proxy_memory_limits             = "64Mi"
    proxy_memory_requests           = "32Mi"
    ztunnel_cpu_limits              = "500m"
    ztunnel_cpu_requests            = "250m"
    ztunnel_memory_limits           = "512Mi"
    ztunnel_memory_requests         = "256Mi"
  }

  assert {
    condition     = helm_release.base.create_namespace
    error_message = "The Istio base release must create istio-system for a fresh cluster."
  }

  assert {
    condition     = helm_release.cni.values[0] == yamlencode({ global = { hub = "mock-docker.pkg.dev/mock-project/mock-virtual/istio" }, platform = "gke", podLabels = { "tags.datadoghq.com/env" = "non-production", "tags.datadoghq.com/service" = "istio-cni", "tags.datadoghq.com/source" = "istio", "tags.datadoghq.com/version" = "1.31.0-rc.0" }, profile = "ambient", resources = { requests = { cpu = "100m", memory = "100Mi" } } })
    error_message = "The shared runtime must preserve the regional wrapper's GKE CNI Helm values."
  }

  assert {
    condition     = yamldecode(helm_release.istiod.values[1]).global.caAddress == "cert-manager-istio-csr.cert-manager.svc:443" && yamldecode(helm_release.istiod.values[1]).env.AMBIENT_ENABLE_MULTI_NETWORK_INGRESS == "true"
    error_message = "The shared runtime must retain the cloud wrapper's CA and ambient multi-network configuration."
  }

  assert {
    condition     = yamldecode(helm_release.ztunnel.values[0]).global.caAddress == "cert-manager-istio-csr.cert-manager.svc:443" && yamldecode(helm_release.ztunnel.values[0]).global.hub == "mock-docker.pkg.dev/mock-project/mock-virtual/istio"
    error_message = "The shared runtime must retain the cloud wrapper's ztunnel CA and image hub."
  }
}

run "local_runtime_profile" {
  command = apply

  module {
    source = "../../../regional/runtime"
  }

  variables {
    ca_address                      = null
    chart_repository                = "https://istio-release.storage.googleapis.com/charts"
    cluster_name                    = "docker-desktop"
    cni_cpu_limits                  = null
    cni_cpu_requests                = "100m"
    cni_memory_limits               = null
    cni_memory_requests             = "100Mi"
    cni_platform                    = ""
    enable_ca_server                = true
    enable_multi_network            = false
    environment                     = "local"
    image_hub                       = "docker.io/istio"
    istio_version                   = "1.31.0-rc.0"
    mesh_config_extension_providers = []
    mesh_config_service_settings    = []
    network                         = "docker-desktop"
    pilot_autoscale_max             = 5
    pilot_autoscale_min             = 1
    pilot_cpu_limits                = "500m"
    pilot_cpu_requests              = "100m"
    pilot_memory_limits             = "512Mi"
    pilot_memory_requests           = "128Mi"
    pilot_replica_count             = 1
    proxy_cpu_limits                = "500m"
    proxy_cpu_requests              = "100m"
    proxy_memory_limits             = "256Mi"
    proxy_memory_requests           = "64Mi"
    ztunnel_cpu_limits              = "500m"
    ztunnel_cpu_requests            = "250m"
    ztunnel_memory_limits           = "512Mi"
    ztunnel_memory_requests         = "256Mi"
  }

  assert {
    condition     = helm_release.base.create_namespace && helm_release.base.version == "1.31.0-rc.0" && helm_release.ztunnel.version == "1.31.0-rc.0"
    error_message = "A fresh local install must bootstrap its namespace and use the published pinned charts."
  }

  assert {
    condition     = helm_release.cni.values[0] == yamlencode({ global = { hub = "docker.io/istio" }, podLabels = { "tags.datadoghq.com/env" = "local", "tags.datadoghq.com/service" = "istio-cni", "tags.datadoghq.com/source" = "istio", "tags.datadoghq.com/version" = "1.31.0-rc.0" }, profile = "ambient", resources = { requests = { cpu = "100m", memory = "100Mi" } } })
    error_message = "The local CNI profile must omit the GKE platform selector and use public images."
  }

  assert {
    condition     = yamldecode(helm_release.istiod.values[1]).env.ENABLE_CA_SERVER == "true" && lookup(yamldecode(helm_release.istiod.values[1]).global, "caAddress", null) == null && lookup(yamldecode(helm_release.ztunnel.values[0]).global, "caAddress", null) == null
    error_message = "The local runtime must use Istio's built-in CA instead of the cloud cert-manager CA."
  }

  assert {
    condition     = yamldecode(helm_release.istiod.values[1]).resources.limits.cpu == "500m" && yamldecode(helm_release.istiod.values[1]).resources.limits.memory == "512Mi" && yamldecode(helm_release.istiod.values[1]).global.proxy.resources.limits.memory == "256Mi"
    error_message = "Local control-plane and proxy limits must be sized for Docker Desktop."
  }
}
