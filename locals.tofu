# Local Values
# https://opentofu.org/docs/language/values/locals

locals {
  gateway_domains = keys(var.gateway_dns)

  gateway_mci_global_address = var.gke_fleet_host_project_id == "" ? google_compute_global_address.istio_gateway_mci.address : ""

  gateway_mci_ssl_certificate_name = var.gke_fleet_host_project_id == "" ? google_compute_managed_ssl_certificate.istio_gateway_mci.name : ""
}
