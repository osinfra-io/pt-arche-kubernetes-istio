# Google Compute Global Address Resource
# https://search.opentofu.org/provider/hashicorp/google/latest/docs/resources/compute_global_address

resource "google_compute_global_address" "istio_gateway_mci" {
  lifecycle {
    enabled = var.gke_fleet_host_project_id == ""
  }

  labels  = var.labels
  name    = "istio-gateway-mci"
  project = var.project
}

# Google Compute Managed SSL Certificate Resource
# https://search.opentofu.org/provider/hashicorp/google/latest/docs/resources/compute_managed_ssl_certificate

# The declarative generation of a Kubernetes ManagedCertificate resource is not supported on
# MultiClusterIngress resources. #36

resource "google_compute_managed_ssl_certificate" "istio_gateway_mci" {
  lifecycle {
    enabled = var.gke_fleet_host_project_id == ""
  }

  managed {
    domains = local.gateway_domains
  }

  name    = "istio-gateway-mci"
  project = var.project
}

# DNS Record Set Resource
# https://search.opentofu.org/provider/hashicorp/google/latest/docs/resources/dns_record_set

resource "google_dns_record_set" "istio_gateway_mcis" {
  for_each = var.gateway_dns

  managed_zone = each.value.managed_zone
  name         = "${each.key}."
  project      = each.value.project
  rrdatas      = [google_compute_global_address.istio_gateway_mci.address]
  ttl          = 300
  type         = "A"
}
