# Local Values
# https://opentofu.org/docs/language/values/locals

locals {
  gateway_dns_record_names = {
    for domain, _ in var.gateway_dns : domain => "${domain}."
  }

  gateway_domains = keys(var.gateway_dns)

  gateway_mci_enabled = var.gke_fleet_host_project_id == ""

  gateway_mci_global_address = local.gateway_mci_enabled ? google_compute_global_address.istio_gateway_mci.address : ""

  gateway_mci_ssl_certificate_name = local.gateway_mci_enabled ? google_compute_managed_ssl_certificate.istio_gateway_mci.name : ""
}
