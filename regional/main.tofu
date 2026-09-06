# Google Compute Global Address Resource
# https://search.opentofu.org/provider/hashicorp/google/latest/docs/resources/compute_global_address

resource "google_compute_global_address" "istio_gateway" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  labels  = var.labels
  name    = local.istio_gateway_name
  project = var.project
}

# DNS Record Set Resource
# https://search.opentofu.org/provider/hashicorp/google/latest/docs/resources/dns_record_set

resource "google_dns_record_set" "istio_gateways" {
  for_each = var.gateway_dns

  managed_zone = each.value.managed_zone
  name         = "${each.key}."
  project      = each.value.project
  rrdatas      = [google_compute_global_address.istio_gateway.address]
  ttl          = 300
  type         = "A"
}

# Helm Release
# https://search.opentofu.org/provider/hashicorp/helm/latest/docs/resources/release

resource "helm_release" "base" {
  chart      = "base"
  name       = "base"
  namespace  = "istio-system"
  repository = var.chart_repository

  version = var.istio_version
}

resource "helm_release" "istiod" {
  depends_on = [
    helm_release.base
  ]

  chart      = "istiod"
  name       = "istiod"
  namespace  = "istio-system"
  repository = var.chart_repository

  values = [
    file("${path.module}/helm/istiod.yml"),
    yamlencode(local.istiod_helm_values)
  ]

  version = var.istio_version
}

# Kubernetes Cluster Role Binding Resource
# https://search.opentofu.org/provider/hashicorp/kubernetes/latest/docs/resources/cluster_role_binding_v1

resource "kubernetes_cluster_role_binding_v1" "istio_reader_gateway_api" {
  depends_on = [
    helm_release.istiod,
    kubernetes_cluster_role_v1.istio_reader_gateway_api
  ]

  metadata {
    name = "istio-reader-gateway-api"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "istio-reader-gateway-api"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "istio-reader-service-account"
    namespace = "istio-system"
  }
}

# Kubernetes Cluster Role Resource
# https://search.opentofu.org/provider/hashicorp/kubernetes/latest/docs/resources/cluster_role_v1

resource "kubernetes_cluster_role_v1" "istio_reader_gateway_api" {
  depends_on = [
    helm_release.istiod
  ]

  metadata {
    name = "istio-reader-gateway-api"
  }

  rule {
    api_groups = ["gateway.networking.k8s.io"]
    resources  = ["grpcroutes", "httproutes", "referencegrants", "tcproutes", "tlsroutes"]
    verbs      = ["get", "list", "watch"]
  }
}

# Kubernetes Config Map Resource
# https://search.opentofu.org/provider/hashicorp/kubernetes/latest/docs/resources/config_map_v1

# Strategic-merge patches applied by istiod to the auto-provisioned gateway data plane. Ports
# the resources, autoscaling, disruption budget, tolerations, topology spread, and Datadog pod
# annotations that were previously set on the Helm gateway release, plus the NodePort Service
# type required by the GKE NEG/MCS ingress path.

resource "kubernetes_config_map_v1" "istio_gateway_options" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  metadata {
    name      = "gateway-options"
    namespace = "istio-ingress"
  }

  data = {
    deployment              = local.istio_gateway_deployment_patch
    horizontalPodAutoscaler = local.istio_gateway_hpa_patch
    podDisruptionBudget     = local.istio_gateway_pdb_patch
    service                 = local.istio_gateway_service_patch
  }
}

# Kubernetes Ingress Resource
# https://search.opentofu.org/provider/hashicorp/kubernetes/latest/docs/resources/ingress_v1

resource "kubernetes_ingress_v1" "istio_gateway" {
  depends_on = [
    kubernetes_manifest.istio_gateway
  ]

  lifecycle {
    enabled = var.enable_istio_gateway
  }

  metadata {
    name      = "istio-gateway"
    namespace = "istio-ingress"

    annotations = {
      "kubernetes.io/ingress.allow-http"            = "false"
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.istio_gateway.name
      "networking.gke.io/v1beta1.FrontendConfig"    = kubernetes_manifest.istio_gateway_frontendconfig.manifest.metadata.name
      "networking.gke.io/managed-certificates"      = kubernetes_manifest.istio_gateway_managed_certificate.manifest.metadata.name
    }
  }

  spec {
    rule {
      http {
        path {
          backend {
            service {
              name = "gateway-istio"
              port {
                number = 443
              }
            }
          }
        }
      }
    }
  }

  wait_for_load_balancer = true
}

# Kubernetes Manifest Resource
# https://search.opentofu.org/provider/hashicorp/kubernetes/latest/docs/resources/manifest

resource "kubernetes_manifest" "istio_gateway" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"

    metadata = {
      name      = "gateway"
      namespace = "istio-ingress"
    }

    spec = {
      gatewayClassName = "istio"

      # istiod provisions the data plane Deployment/Service (named gateway-istio) from this
      # Gateway. Datadog labels and the GKE Service annotations are copied onto the generated
      # resources via infrastructure; the parametersRef ConfigMap carries the strategic-merge
      # patches for the Service (NodePort), Deployment, HPA, and PodDisruptionBudget.

      infrastructure = {
        annotations = {
          "cloud.google.com/app-protocols"  = jsonencode({ "https" = "HTTPS" })
          "cloud.google.com/backend-config" = jsonencode({ "default" = "istio-gateway-backend" })
          "cloud.google.com/neg"            = jsonencode({ "ingress" = true })

          # Suppress IST0170: The MCS only exports port 443 (not status-port 15021) by design,
          # so Istio sees inconsistent ports across clusters. This is expected.
          "galley.istio.io/analyze-suppress" = "IST0170"
        }

        labels = {
          "tags.datadoghq.com/env"     = module.core_helpers.environment
          "tags.datadoghq.com/service" = "istio-gateway"
          "tags.datadoghq.com/source"  = "envoy"
          "tags.datadoghq.com/version" = var.istio_version
        }

        parametersRef = {
          group = ""
          kind  = "ConfigMap"
          name  = kubernetes_config_map_v1.istio_gateway_options.metadata[0].name
        }
      }

      listeners = local.gateway_listeners
    }
  }
}

# Kubernetes Manifest Resource
# https://search.opentofu.org/provider/hashicorp/kubernetes/latest/docs/resources/manifest

resource "kubernetes_manifest" "istio_gateway_backendconfig" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  manifest = {
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      name      = "istio-gateway-backend"
      namespace = "istio-ingress"
    }
    spec = {
      healthCheck = {
        checkIntervalSec   = "5"
        healthyThreshold   = "1"
        port               = "15021"
        requestPath        = "/healthz/ready"
        timeoutSec         = "3"
        type               = "HTTP"
        unhealthyThreshold = "2"
      }
      securityPolicy = {
        name = "istio-gateway"
      }
    }
  }
}

resource "kubernetes_manifest" "istio_gateway_ca_certificate" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "istio-gateway-ca"
      namespace = "istio-ingress"
    }

    spec = {
      commonName = "istio-gateway-intermediate-ca.osinfra.io"
      duration   = "720h"
      isCA       = true

      issuerRef = {
        group = "cert-manager.io"
        kind  = "Issuer"
        name  = kubernetes_manifest.istio_gateway_intermediate_ca_issuer.manifest.metadata.name
      }

      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }

      secretName = "istio-gateway-ca"

      subject = {
        organizations = ["Open Source Infrastructure (as Code) Istio Gateway Intermediate CA"]
      }
    }
  }
}

resource "kubernetes_manifest" "istio_gateway_frontendconfig" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  manifest = {
    apiVersion = "networking.gke.io/v1beta1"
    kind       = "FrontendConfig"
    metadata = {
      name      = "istio-gateway-frontend"
      namespace = "istio-ingress"
    }
    spec = {
      redirectToHttps = {
        enabled = true
      }
      sslPolicy = "istio-gateway"
    }
  }
}

resource "kubernetes_manifest" "istio_gateway_intermediate_ca_issuer" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"

    metadata = {
      name      = "istio-gateway-intermediate-ca"
      namespace = "istio-ingress"
    }

    spec = {
      ca = {
        secretName = kubernetes_secret_v1.istio_cert_manager_ca.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "istio_gateway_managed_certificate" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = "istio-gateway-tls"
      namespace = "istio-ingress"
    }
    spec = {
      domains = local.gateway_domains
    }
  }
}

resource "kubernetes_manifest" "istio_gateway_mci" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "MultiClusterIngress"

    metadata = {
      annotations = {
        "networking.gke.io/frontend-config"  = kubernetes_manifest.istio_gateway_frontendconfig.manifest.metadata.name
        "networking.gke.io/pre-shared-certs" = "istio-gateway-mci"
        "networking.gke.io/static-ip"        = var.gateway_mci_global_address
      }
      name      = "istio-gateway-mci"
      namespace = "istio-ingress"
    }

    spec = {
      template = {
        spec = {
          backend = {
            serviceName = kubernetes_manifest.istio_gateway_mcs.manifest.metadata.name
            servicePort = kubernetes_manifest.istio_gateway_mcs.manifest.spec.template.spec.ports[0].port
          }
          rules = [
            {
              http = {
                paths = [
                  {
                    backend = {
                      serviceName = kubernetes_manifest.istio_gateway_mcs.manifest.metadata.name
                      servicePort = kubernetes_manifest.istio_gateway_mcs.manifest.spec.template.spec.ports[0].port
                    }
                  }
                ]
              }
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "istio_gateway_mcs" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "MultiClusterService"

    metadata = {
      annotations = {
        "cloud.google.com/backend-config" = jsonencode({ "default" = "${kubernetes_manifest.istio_gateway_backendconfig.manifest.metadata.name}" })
        "cloud.google.com/neg"            = jsonencode({ "ingress" = true })
        "networking.gke.io/app-protocols" = jsonencode({ "https" = "HTTPS" })
      }
      name      = "istio-gateway-mcs"
      namespace = "istio-ingress"
    }

    spec = {
      template = {
        spec = {
          selector = {
            "gateway.networking.k8s.io/gateway-name" = "gateway"
          }

          ports = [
            {
              name       = "https"
              port       = 443
              protocol   = "TCP"
              targetPort = 443
            }
          ]
        }
      }

      clusters = var.multi_cluster_service_clusters
    }
  }
}

resource "kubernetes_manifest" "istio_gateway_tls" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "istio-gateway-tls"
      namespace = "istio-ingress"
    }

    spec = {
      commonName = "istio-gateway.osinfra.io"
      dnsNames   = ["*"]
      duration   = "720h"
      isCA       = false

      issuerRef = {
        group = "cert-manager.io"
        kind  = "Issuer"
        name  = kubernetes_manifest.istio_gateway_intermediate_ca_issuer.manifest.metadata.name
      }

      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }

      secretName = "istio-gateway-tls"

      subject = {
        organizations = ["Open Source Infrastructure (as Code) Istio Gateway"]
      }
    }
  }
}

# Kubernetes Secret Resource
# https://search.opentofu.org/provider/hashicorp/kubernetes/latest/docs/resources/secret_v1

resource "kubernetes_secret_v1" "istio_cert_manager_ca" {
  lifecycle {
    enabled = var.enable_istio_gateway
  }

  metadata {
    name      = "cert-manager-ca"
    namespace = "istio-ingress"
  }

  data = {
    "tls.crt" = var.tls_self_signed_cert_cert_manager_root_cert
    "tls.key" = var.tls_self_signed_cert_cert_manager_root_key
  }
}
