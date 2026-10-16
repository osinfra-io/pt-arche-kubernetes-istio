# Input Variables
# https://opentofu.org/docs/language/values/variables

variable "gateway_dns" {
  description = "Map of attributes for the Istio gateway domain names, it is also used to create the managed certificate resource"
  type = map(object({
    managed_zone = string
    project      = string
  }))
  default = {}
}

variable "gke_fleet_host_project_id" {
  description = "The project ID of the GKE Hub host project"
  type        = string
  default     = ""
}

variable "labels" {
  description = "A map of key/value pairs to assign to the resources being created"
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "The ID of the project in which the resource belongs"
  type        = string
}
