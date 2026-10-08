# Input Variables
# https://opentofu.org/docs/language/values/variables

variable "ca_address" {
  description = "The certificate authority address for workload certificates; null uses Istio's built-in CA"
  type        = string
  default     = "cert-manager-istio-csr.cert-manager.svc:443"
}

variable "chart_repository" {
  description = "The repository to pull the Istio Helm charts from"
  type        = string
  default     = "https://istio-release.storage.googleapis.com/charts"
}

variable "cluster_name" {
  description = "The Istio cluster name"
  type        = string
}

variable "cni_cpu_limits" {
  description = "The CPU limit for the Istio CNI node agent"
  type        = string
  default     = null
}

variable "cni_cpu_requests" {
  description = "The CPU request for the Istio CNI node agent"
  type        = string
}

variable "cni_memory_limits" {
  description = "The memory limit for the Istio CNI node agent"
  type        = string
  default     = null
}

variable "cni_memory_requests" {
  description = "The memory request for the Istio CNI node agent"
  type        = string
}

variable "cni_platform" {
  description = "Istio CNI platform profile; empty leaves the upstream Kind-compatible profile selected"
  type        = string
}

variable "enable_ca_server" {
  description = "Whether istiod serves workload certificates using its built-in CA"
  type        = bool
  default     = false
}

variable "enable_multi_network" {
  description = "Enable Istio ambient multi-network control plane settings"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment label applied to Istio workloads"
  type        = string
}

variable "image_hub" {
  description = "Image registry hub used by Istio charts"
  type        = string
}

variable "mesh_config_extension_providers" {
  description = "Istio meshConfig extensionProviders entries"
  type        = list(any)
  default     = []
}

variable "mesh_config_service_settings" {
  description = "Istio meshConfig serviceSettings entries"
  type        = list(any)
  default     = []
}

variable "network" {
  description = "The Istio network name"
  type        = string
}

variable "pilot_autoscale_max" {
  description = "The maximum number of Istio pilot replicas"
  type        = number
}

variable "pilot_autoscale_min" {
  description = "The minimum number of Istio pilot replicas"
  type        = number
}

variable "pilot_cpu_limits" {
  description = "The CPU limit for istiod"
  type        = string
}

variable "pilot_cpu_requests" {
  description = "The CPU request for istiod"
  type        = string
}

variable "pilot_memory_limits" {
  description = "The memory limit for istiod"
  type        = string
}

variable "pilot_memory_requests" {
  description = "The memory request for istiod"
  type        = string
}

variable "pilot_replica_count" {
  description = "The number of Istio pilot replicas"
  type        = number
}

variable "proxy_cpu_limits" {
  description = "The CPU limit for the Istio proxy"
  type        = string
}

variable "proxy_cpu_requests" {
  description = "The CPU request for the Istio proxy"
  type        = string
}

variable "proxy_memory_limits" {
  description = "The memory limit for the Istio proxy"
  type        = string
}

variable "proxy_memory_requests" {
  description = "The memory request for the Istio proxy"
  type        = string
}

variable "ztunnel_cpu_limits" {
  description = "The CPU limit for ztunnel"
  type        = string
}

variable "ztunnel_cpu_requests" {
  description = "The CPU request for ztunnel"
  type        = string
}

variable "ztunnel_memory_limits" {
  description = "The memory limit for ztunnel"
  type        = string
}

variable "ztunnel_memory_requests" {
  description = "The memory request for ztunnel"
  type        = string
}
