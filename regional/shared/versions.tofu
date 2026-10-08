# Input Variables
# https://opentofu.org/docs/language/values/variables

variable "istio_version" {
  # Temporarily pinned to the 1.31.0-rc.0 chart: the 1.31.0/1.31.1 GA charts
  # were never published to the istio-release Helm chart bucket (only
  # pre-release rc/beta/alpha charts exist there), even though the GitHub
  # binary release and docs for 1.31.1 are live. Re-pin to the GA version
  # once the chart publish gap is resolved upstream.
  description = "The version to install, this is used for the chart as well as the image tag"
  type        = string
  default     = "1.31.0-rc.0"
}
