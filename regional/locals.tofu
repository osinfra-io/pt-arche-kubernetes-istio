# Local Values
# https://opentofu.org/docs/language/values/locals

locals {
  gateway_domains = keys(var.gateway_dns)

  # Gateway listener. A single catch-all HTTPS listener terminates TLS for every
  # team's traffic. hostname is null so Envoy builds a default (no-SNI) filter
  # chain: the fronting GCP L7 load balancer re-originates TLS to the backend
  # without forwarding client SNI, so an SNI-matched chain would never match.
  # allowedRoutes.from is All because per-team isolation is enforced upstream in
  # IaC/workflows (route intent is declared in Logos and PR-reviewed, HTTPRoute
  # hostnames are derived from each team's authoritative DNS zone, and only the
  # deploy workflow applies routes), not at runtime by the gateway. The
  # istio-gateway-tls wildcard certificate covers every host.
  gateway_listeners = [
    {
      allowedRoutes = {
        namespaces = {
          from = "All"

          selector = null
        }
      }

      # hostname is intentionally absent — the field is omitted, not set to null. A listener with
      # no hostname is catch-all, and the kubernetes_manifest provider treats an explicit null as
      # a known-after-apply value, which produces a perpetual in-place diff on every plan.
      name     = "https"
      port     = 443
      protocol = "HTTPS"

      tls = {
        certificateRefs = [
          {
            kind = "Secret"
            name = "istio-gateway-tls"
          }
        ]

        mode = "Terminate"
      }
    }
  ]

  istio_gateway_address = var.enable_istio_gateway ? google_compute_global_address.istio_gateway.address : null

  # Strategic-merge patch for the generated gateway Deployment. istiod names the gateway
  # container "istio-proxy". Ports the resources, tolerations, and topology spread that were
  # set on the Helm gateway release.
  istio_gateway_deployment_patch = yamlencode({
    spec = {
      template = {
        spec = {
          containers = [
            {
              name = "istio-proxy"

              resources = {
                limits = {
                  cpu    = var.gateway_cpu_limits
                  memory = var.gateway_memory_limits
                }

                requests = {
                  cpu    = var.gateway_cpu_requests
                  memory = var.gateway_memory_requests
                }
              }
            }
          ]

          tolerations = [
            {
              effect = "NoExecute"
              key    = "dedicated"
              value  = "gateway"
            }
          ]

          topologySpreadConstraints = [
            {
              labelSelector = {
                matchLabels = {
                  "gateway.networking.k8s.io/gateway-name" = "gateway"
                }
              }

              maxSkew           = 1
              topologyKey       = "topology.kubernetes.io/zone"
              whenUnsatisfiable = "ScheduleAnyway"
            }
          ]
        }
      }
    }
  })

  # Strategic-merge patch creating a HorizontalPodAutoscaler for the generated gateway
  # Deployment (istiod wires the scaleTargetRef automatically).
  istio_gateway_hpa_patch = yamlencode({
    spec = {
      maxReplicas = var.gateway_autoscale_max

      metrics = [
        {
          resource = {
            name = "cpu"

            target = {
              averageUtilization = 85
              type               = "Utilization"
            }
          }

          type = "Resource"
        }
      ]

      minReplicas = var.gateway_autoscale_min
    }
  })

  # Strategic-merge patch creating a PodDisruptionBudget for the generated gateway Deployment.
  istio_gateway_pdb_patch = yamlencode({
    spec = {
      maxUnavailable = 1
    }
  })

  # Strategic-merge patch setting the generated gateway Service type to NodePort, required by
  # the GKE NEG/MultiClusterIngress path (the default is LoadBalancer).
  istio_gateway_service_patch = yamlencode({
    spec = {
      type = "NodePort"
    }
  })

  istio_gateway_name = "istio-gateway-${module.core_helpers.region}-${module.core_helpers.zone}"

  # East-west gateway listener. HBONE-only, double-HBONE terminate, per the ambient
  # multicluster install guide — this is the only supported ambient east-west shape.
  istio_east_west_gateway_listeners = [
    {
      name     = "mesh"
      port     = 15008
      protocol = "HBONE"

      tls = {
        mode = "Terminate"

        options = {
          "gateway.istio.io/tls-terminate-mode" = "ISTIO_MUTUAL"
        }
      }
    }
  ]

  # Every cluster is its own logical Istio network so cross-cluster ambient traffic takes the
  # supported multi-network east-west gateway path (same-network ambient multicluster is
  # untested upstream).
  istio_network = local.multi_cluster_name

  istiod_helm_values = {
    autoscaleMax = var.pilot_autoscale_max
    autoscaleMin = var.pilot_autoscale_min

    deploymentLabels = {
      "tags.datadoghq.com/env"     = module.core_helpers.environment
      "tags.datadoghq.com/version" = var.istio_version
    }

    # Ambient multi-network multicluster flags per the upstream install guide.
    # AMBIENT_ENABLE_MULTI_NETWORK_INGRESS lets ingress Gateway proxies route to endpoints in
    # remote networks via their east-west gateways.
    env = {
      AMBIENT_ENABLE_BAGGAGE               = "true"
      AMBIENT_ENABLE_MULTI_NETWORK         = "true"
      AMBIENT_ENABLE_MULTI_NETWORK_INGRESS = "true"
    }

    global = {
      hub = "${var.artifact_registry}/istio"

      multiCluster = {
        clusterName = local.multi_cluster_name
      }

      network = local.istio_network

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
    }

    # All mesh config is rendered by Helm — never patch the istio ConfigMap out-of-band, which
    # drops every other rendered key (including the ambient profile's serviceScopeConfigs).
    meshConfig = {
      extensionProviders = var.mesh_config_extension_providers
      serviceSettings    = var.mesh_config_service_settings
    }

    podLabels = {
      "tags.datadoghq.com/env"     = module.core_helpers.environment
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

  multi_cluster_name = module.core_helpers.zone != null ? "${var.cluster_prefix}-${module.core_helpers.region}-${module.core_helpers.zone}-${module.core_helpers.env}" : "${var.cluster_prefix}-${module.core_helpers.region}-${module.core_helpers.env}"
}
