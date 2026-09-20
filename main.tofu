# Google Compute Global Address Resource
# https://search.opentofu.org/provider/hashicorp/google/latest/docs/resources/compute_global_address

resource "google_compute_global_address" "istio_gateway_mci" {
  lifecycle {
    enabled = var.gke_fleet_host_project_id == ""
  }

  labels  = var.labels
  name    = "istio-gateway-mci"
  project = var.project
}

# Google Compute Managed SSL Certificate Resource
# https://search.opentofu.org/provider/hashicorp/google/latest/docs/resources/compute_managed_ssl_certificate

# The declarative generation of a Kubernetes ManagedCertificate resource is not supported on
# MultiClusterIngress resources. #36

resource "google_compute_managed_ssl_certificate" "istio_gateway_mci" {
  lifecycle {
    enabled = var.gke_fleet_host_project_id == ""
  }

  managed {
    domains = local.gateway_domains
  }

  name    = "istio-gateway-mci"
  project = var.project
}

# Google Compute Security Policy Resource
# https://search.opentofu.org/provider/hashicorp/google/latest/docs/resources/compute_security_policy

resource "google_compute_security_policy" "istio_gateway" {
  lifecycle {
    enabled = var.gke_fleet_host_project_id == ""
  }

  provider = google-beta # Required for the adaptive_protection_config auto_deploy_config block

  adaptive_protection_config {
    auto_deploy_config {

      # Rules are only automatically deployed for alerts on potential attacks with confidence scores greater than this threshold.

      confidence_threshold = "0.5"

      # Google Cloud Armor stops applying the action in the automatically deployed rule to an identified attacker after this duration.

      expiration_sec = 7200

      # Rules are only automatically deployed when the estimated impact to baseline traffic from the suggested mitigation is below this threshold

      impacted_baseline_threshold = "0.01"

      # During an alerted attack, Adaptive Protection identifies new attackers only when the load to the backend service that is under attack exceeds this threshold.

      load_threshold = "0.8"
    }

    layer_7_ddos_defense_config {
      enable = true
    }
  }

  advanced_options_config {
    log_level = "VERBOSE"
  }

  name    = "istio-gateway"
  project = var.project

  dynamic "rule" {
    for_each = var.cloud_armor_allow_rules

    content {
      action      = "allow"
      description = rule.value.description

      match {
        expr {
          expression = rule.value.expression
        }
      }

      preview  = false
      priority = rule.value.priority
    }
  }

  rule {
    action      = "throttle"
    description = "Rate limit all user IPs"

    match {
      config {
        src_ip_ranges = ["*"]
      }

      versioned_expr = "SRC_IPS_V1"
    }

    preview  = false
    priority = "30000"

    rate_limit_options {
      conform_action = "allow"
      enforce_on_key = "ALL"
      exceed_action  = "deny(429)"

      rate_limit_threshold {
        count        = "500"
        interval_sec = "60"
      }
    }
  }

  rule {
    action      = "allow"
    description = "Default allow rule"

    match {
      config {
        src_ip_ranges = ["*"]
      }

      versioned_expr = "SRC_IPS_V1"
    }

    priority = "2147483647" # Use the maximum allowed priority value to ensure this is the default rule
  }

  dynamic "rule" {
    for_each = local.preconfigured_waf_rules

    content {
      action      = rule.value.action
      description = rule.value.description

      match {
        expr {
          expression = "evaluatePreconfiguredWaf('${rule.value.name}', {'sensitivity': ${rule.value.sensitivity}})"
        }
      }

      dynamic "preconfigured_waf_config" {
        for_each = length(local.waf_exclusions_by_rule_set[rule.value.name]) > 0 ? [1] : []

        content {
          dynamic "exclusion" {
            for_each = local.waf_exclusions_by_rule_set[rule.value.name]

            content {
              target_rule_ids = exclusion.value.target_rule_ids
              target_rule_set = exclusion.value.target_rule_set

              dynamic "request_query_param" {
                for_each = exclusion.value.request_query_param_names

                content {
                  operator = "EQUALS"
                  value    = request_query_param.value
                }
              }
            }
          }
        }
      }

      preview  = rule.value.preview
      priority = rule.value.priority
    }
  }
}

# Google Compute SSL Policy Resource
# https://search.opentofu.org/provider/hashicorp/google/latest/docs/resources/compute_ssl_policy

resource "google_compute_ssl_policy" "istio_gateway" {
  lifecycle {
    enabled = var.gke_fleet_host_project_id == ""
  }

  min_tls_version = "TLS_1_2"
  name            = "istio-gateway"
  profile         = "MODERN"
  project         = var.project
}

# DNS Record Set Resource
# https://search.opentofu.org/provider/hashicorp/google/latest/docs/resources/dns_record_set

resource "google_dns_record_set" "istio_gateway_mcis" {
  for_each = var.gateway_dns

  managed_zone = each.value.managed_zone
  name         = "${each.key}."
  project      = each.value.project
  rrdatas      = [google_compute_global_address.istio_gateway_mci.address]
  ttl          = 300
  type         = "A"
}
