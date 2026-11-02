# Output Values
# https://opentofu.org/docs/language/values/outputs

output "gateway_mci_global_address" {
  description = "The IP address for the Istio Gateway multi-cluster ingress"
  value       = local.gateway_mci_global_address
}

output "gateway_mci_ssl_certificate_names" {
  description = "The names of the SSL certificates to attach to the Istio Gateway multi-cluster ingress, current certificate first"
  value       = local.gateway_attached_certificate_names
}
