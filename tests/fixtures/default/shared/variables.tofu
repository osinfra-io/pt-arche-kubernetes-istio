# Input Variables
# https://opentofu.org/docs/language/values/variables

variable "gateway_dns" {
  description = "Map of DNS configurations for the Istio Gateway"
  type = map(object({
    managed_zone = string
    project      = string
  }))
}

variable "gateway_retained_domain_sets" {
  description = "Previous gateway domain sets whose certificates are kept"
  type        = list(list(string))
  default     = []
}

variable "project" {
  description = "The GCP project ID"
  type        = string
}
