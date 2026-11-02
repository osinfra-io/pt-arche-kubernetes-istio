# Local Values
# https://opentofu.org/docs/language/values/locals

locals {
  # The current domain set comes first so its certificate leads the pre-shared-certs list.
  # Retained certificates stay managed but are only attached while gateway_attach_retained_certificates is true.
  gateway_attached_certificate_names = slice(
    local.gateway_certificate_names,
    0,
    var.gateway_attach_retained_certificates ? length(local.gateway_certificate_names) : min(1, length(local.gateway_certificate_names))
  )

  gateway_certificate_domain_sets = local.gateway_mci_enabled ? [
    for domain_set in concat([local.gateway_domains], var.gateway_retained_domain_sets) : sort(domain_set)
    if length(domain_set) > 0
  ] : []

  gateway_certificate_names = distinct([
    for domain_set in local.gateway_certificate_domain_sets :
    "istio-gateway-mci-${substr(sha256(join(",", domain_set)), 0, 8)}"
  ])

  gateway_certificates = {
    for name, domain_sets in {
      for domain_set in local.gateway_certificate_domain_sets :
      "istio-gateway-mci-${substr(sha256(join(",", domain_set)), 0, 8)}" => domain_set...
    } : name => domain_sets[0]
  }

  gateway_dns_record_names = {
    for domain, _ in var.gateway_dns : domain => "${domain}."
  }

  gateway_domains = keys(var.gateway_dns)

  gateway_mci_enabled = var.gke_fleet_host_project_id == ""

  gateway_mci_global_address = local.gateway_mci_enabled ? google_compute_global_address.istio_gateway_mci.address : ""
}
