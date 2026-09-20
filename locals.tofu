# Local Values
# https://opentofu.org/docs/language/values/locals

locals {
  gateway_domains = keys(var.gateway_dns)

  gateway_mci_global_address = var.gke_fleet_host_project_id == "" ? google_compute_global_address.istio_gateway_mci.address : ""

  gateway_mci_ssl_certificate_name = var.gke_fleet_host_project_id == "" ? google_compute_managed_ssl_certificate.istio_gateway_mci.name : ""

  preconfigured_waf_rules = [
    # Google Cloud Armor provides preconfigured WAF rules, each consisting of multiple signatures sourced from:
    # https://github.com/coreruleset/coreruleset/releases/tag/v3.3.3

    # Each signature has a sensitivity level that corresponds to a ModSecurity paranoia level. You can select a
    # sensitivity between 0 and 4, though sensitivity level 0 means that no rules are enabled by default.
    # A lower sensitivity level indicates higher confidence signatures, which are less likely to generate a false positive.
    # A higher sensitivity level increases security, but also increases the risk of generating a false positive.

    {
      action      = "deny(403)"
      description = "OWASP: SQL injection"
      name        = "sqli-v33-stable"
      preview     = false
      priority    = 10000
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "OWASP: Cross-site scripting"
      name        = "xss-v33-stable"
      preview     = false
      priority    = 10010
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "OWASP: Local file inclusion"
      name        = "lfi-v33-stable"
      preview     = false
      priority    = 10020
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "OWASP: Remote file inclusion"
      name        = "rfi-v33-stable"
      preview     = false
      priority    = 10030
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "OWASP: Remote code execution"
      name        = "rce-v33-stable"
      preview     = false
      priority    = 10040
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "OWASP: Method enforcement"
      name        = "methodenforcement-v33-stable"
      preview     = false
      priority    = 10050
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "OWASP: Scanner detection"
      name        = "scannerdetection-v33-stable"
      preview     = false
      priority    = 10060
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "OWASP: Protocol attack"
      name        = "protocolattack-v33-stable"
      preview     = false
      priority    = 10070
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "OWASP: PHP injection attack"
      name        = "php-v33-stable"
      preview     = false
      priority    = 10080
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "OWASP: Session fixation"
      name        = "sessionfixation-v33-stable"
      preview     = false
      priority    = 10090
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "OWASP: Java attack"
      name        = "java-v33-stable"
      preview     = false
      priority    = 10100
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "OWASP: NodeJS attack"
      name        = "nodejs-v33-stable"
      preview     = false
      priority    = 10110
      sensitivity = 1
    },

    # Additional rules that detect and optionally block the following
    # vulnerabilities:

    # CVE-2021-44228 and CVE-2021-45046 Log4j RCE vulnerabilities
    # 942550-sqli JSON-formatted content vulnerability

    {
      action      = "deny(403)"
      description = "Log4j vulnerability"
      name        = "cve-canary"
      preview     = false
      priority    = 10120
      sensitivity = 1
    },
    {
      action      = "deny(403)"
      description = "JSON-based SQL injection bypass vulnerability"
      name        = "json-sqli-canary"
      preview     = false
      priority    = 10130
      sensitivity = 1
    }
  ]

  # Groups var.cloud_armor_waf_exclusions by preconfigured rule set name so the rule dynamic block
  # above can look up the exclusions (if any) that apply to each preconfigured WAF rule it renders.
  waf_exclusions_by_rule_set = {
    for rule in local.preconfigured_waf_rules : rule.name => [
      for exclusion in var.cloud_armor_waf_exclusions : exclusion
      if exclusion.target_rule_set == rule.name
    ]
  }
}
