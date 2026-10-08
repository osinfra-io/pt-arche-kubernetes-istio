# Local Values
# https://opentofu.org/docs/language/values/locals

locals {
  cni_helm_values = merge(
    var.cni_platform == "" ? {} : { platform = var.cni_platform },
    {
      global = {
        hub = var.image_hub
      }

      podLabels = {
        "tags.datadoghq.com/env"     = var.environment
        "tags.datadoghq.com/service" = "istio-cni"
        "tags.datadoghq.com/source"  = "istio"
        "tags.datadoghq.com/version" = var.istio_version
      }

      profile = "ambient"

      resources = merge(
        {
          requests = {
            cpu    = var.cni_cpu_requests
            memory = var.cni_memory_requests
          }
        },
        length(local.cni_limits) > 0 ? { limits = local.cni_limits } : {}
      )
    }
  )

  cni_limits = {
    for k, v in {
      cpu    = var.cni_cpu_limits
      memory = var.cni_memory_limits
    } : k => v if v != null
  }

  istiod_helm_values = {
    autoscaleMax = var.pilot_autoscale_max
    autoscaleMin = var.pilot_autoscale_min

    deploymentLabels = {
      "tags.datadoghq.com/env"     = var.environment
      "tags.datadoghq.com/version" = var.istio_version
    }

    env = merge(
      {
        AMBIENT_ENABLE_BAGGAGE = "true"
        ENABLE_CA_SERVER       = tostring(var.enable_ca_server)
      },
      var.enable_multi_network ? {
        AMBIENT_ENABLE_MULTI_NETWORK         = "true"
        AMBIENT_ENABLE_MULTI_NETWORK_INGRESS = "true"
      } : {}
    )

    global = merge(
      {
        hub = var.image_hub

        multiCluster = {
          clusterName = var.cluster_name
        }

        network = var.network

        proxy = {
          resources = {
            limits = {
              cpu    = var.proxy_cpu_limits
              memory = var.proxy_memory_limits
            }

            requests = {
              cpu    = var.proxy_cpu_requests
              memory = var.proxy_memory_requests
            }
          }
        }
      },
      var.ca_address == null ? { caAddress = null } : { caAddress = var.ca_address }
    )

    meshConfig = {
      extensionProviders = var.mesh_config_extension_providers
      serviceSettings    = var.mesh_config_service_settings
    }

    podLabels = {
      "tags.datadoghq.com/env"     = var.environment
      "tags.datadoghq.com/version" = var.istio_version
    }

    replicaCount = var.pilot_replica_count

    resources = {
      limits = {
        cpu    = var.pilot_cpu_limits
        memory = var.pilot_memory_limits
      }

      requests = {
        cpu    = var.pilot_cpu_requests
        memory = var.pilot_memory_requests
      }
    }
  }

  ztunnel_global_values = var.ca_address == null ? {} : { caAddress = var.ca_address }

  ztunnel_helm_values = {
    global = merge(
      local.ztunnel_global_values,
      {
        hub     = var.image_hub
        network = var.network
      }
    )

    multiCluster = {
      clusterName = var.cluster_name
    }

    podLabels = {
      "tags.datadoghq.com/env"     = var.environment
      "tags.datadoghq.com/service" = "istio-ztunnel"
      "tags.datadoghq.com/source"  = "istio"
      "tags.datadoghq.com/version" = var.istio_version
    }

    resources = {
      limits = {
        cpu    = var.ztunnel_cpu_limits
        memory = var.ztunnel_memory_limits
      }

      requests = {
        cpu    = var.ztunnel_cpu_requests
        memory = var.ztunnel_memory_requests
      }
    }
  }
}
