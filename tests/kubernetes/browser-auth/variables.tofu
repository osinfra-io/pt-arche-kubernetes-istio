# Input Variables
# https://opentofu.org/docs/language/values/variables

variable "revoke_application_access" {
  default     = false
  description = "Local-only revocation test: temporarily deny declared application access without changing Logos or diagnostic access."
  type        = bool
}

variable "teams" {
  description = "Actual Logos team declaration passed by the owning local apply script."
  type = map(object({
    authentik_groups = optional(map(object({
      description = string
      label       = string
      members = optional(object({
        non-production = optional(list(string), [])
        production     = optional(list(string), [])
        sandbox        = optional(list(string), [])
      }), {})
    })), {})
  }))
}
