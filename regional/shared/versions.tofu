# Input Variables
# https://opentofu.org/docs/language/values/variables

variable "istio_version" {
  description = "The version to install, this is used for the chart as well as the image tag"
  type        = string
  default     = "1.31.2"
}
