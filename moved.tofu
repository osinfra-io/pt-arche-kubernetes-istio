# Moved Blocks
# https://opentofu.org/docs/language/modules/develop/refactoring

# The single fixed-name certificate is replaced by hash-named certificates. Drop it from state
# without deleting it because the load balancer still references it until the regional workspaces
# attach the new certificate; delete the orphaned "istio-gateway-mci" certificate afterwards.

removed {
  from = google_compute_managed_ssl_certificate.istio_gateway_mci

  lifecycle {
    destroy = false
  }
}
