# Input Variables
# https://opentofu.org/docs/language/values/variables

variable "cloud_armor_allow_rules" {
  description = "Map of authenticated request exceptions evaluated before the preconfigured Cloud Armor WAF rules"
  type = map(object({
    description = string
    expression  = string
    priority    = number
  }))
  default = {}

  validation {
    condition = alltrue([
      for rule in values(var.cloud_armor_allow_rules) :
      rule.priority == floor(rule.priority) && rule.priority > 0 && rule.priority < 10000
    ])
    error_message = "Cloud Armor allow rule priorities must be integers between 1 and 9999 so they run before the preconfigured WAF rules."
  }

  validation {
    condition     = length(distinct([for rule in values(var.cloud_armor_allow_rules) : rule.priority])) == length(var.cloud_armor_allow_rules)
    error_message = "Cloud Armor allow rule priorities must be unique."
  }
}

variable "cloud_armor_waf_exclusions" {
  description = "Scoped preconfigured WAF exclusions that exclude specific request query parameter values from inspection by specific rule IDs, instead of allowing the entire request past every preconfigured WAF rule"
  type = list(object({
    request_query_param_names = list(string)
    target_rule_ids           = list(string)
    target_rule_set           = string
  }))
  default = []
}

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
