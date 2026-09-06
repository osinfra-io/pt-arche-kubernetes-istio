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
  # container "istio-proxy". Ports the resources, tolerations, topology spread, and Datadog
  # pod annotations (autodiscovery, APM env, and Istio proxy tracing config) that were set on
  # the Helm gateway release.
  istio_gateway_deployment_patch = yamlencode({
    spec = {
      template = {
        metadata = {
          annotations = {
            "ad.datadoghq.com/istio-proxy.check_names"  = "[\"envoy\"]"
            "ad.datadoghq.com/istio-proxy.init_configs" = "[{}]"
            "ad.datadoghq.com/istio-proxy.instances"    = "[\n  {\n   \"openmetrics_endpoint\": \"http://%%host%%:15020/stats/prometheus\"\n  }\n]\n"
            "ad.datadoghq.com/istio-proxy.logs"         = "[{\"source\":\"envoy\"}]"

            "apm.datadoghq.com/env" = jsonencode({
              DD_ENV     = module.core_helpers.environment
              DD_SERVICE = "istio-gateway"
              DD_VERSION = var.istio_version
            })

            "proxy.istio.io/config" = yamlencode({
              proxyMetadata = {
                DD_ENV     = module.core_helpers.environment
                DD_SERVICE = "istio-gateway"
                DD_VERSION = var.istio_version
              }

              tracing = {
                datadog = {
                  address = "$(HOST_IP):8126"
                }
              }
            })
          }
        }

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

  istiod_helm_values = {
    autoscaleMin = var.pilot_autoscale_min

    deploymentLabels = {
      "tags.datadoghq.com/env"     = module.core_helpers.environment
      "tags.datadoghq.com/version" = var.istio_version
    }

    global = {
      hub = "${var.artifact_registry}/istio"

      multiCluster = {
        clusterName = local.multi_cluster_name
      }

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
