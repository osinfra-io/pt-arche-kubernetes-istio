# Input Variables
# https://opentofu.org/docs/language/values/variables

variable "gateway_dns" {
  description = "Map of DNS configurations for the Istio Gateway"
  type = map(object({
    managed_zone = string
    project      = string
  }))
}

variable "project" {
  description = "The GCP project ID"
  type        = string
}
