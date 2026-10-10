mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project = "mock-project"
}

run "default_method_enforcement" {
  command = plan

  assert {
    condition     = local.waf_rule_expressions["methodenforcement-v33-stable"] == "evaluatePreconfiguredWaf('methodenforcement-v33-stable', {'sensitivity': 1})"
    error_message = "Without exceptions, method enforcement must remain unchanged."
  }
}

run "scoped_api_methods" {
  command = plan

  variables {
    cloud_armor_method_enforcement_exceptions = [
      {
        hostname    = "authentik.sb.osinfra.io"
        methods     = ["DELETE", "PATCH", "PUT"]
        path_prefix = "/api/v3/"
      }
    ]
  }

  assert {
    condition     = local.waf_rule_expressions["methodenforcement-v33-stable"] == "evaluatePreconfiguredWaf('methodenforcement-v33-stable', {'sensitivity': 1}) && !((has(request.headers['host']) && request.headers['host'] == \"authentik.sb.osinfra.io\" && request.path.startsWith(\"/api/v3/\") && request.method.matches(\"^DELETE$|^PATCH$|^PUT$\")))"
    error_message = "The exception must match only the configured host, API path boundary, and methods."
  }

  assert {
    condition = alltrue([
      for method in ["DELETE", "PATCH", "PUT"] :
      can(regex(regex("request\\.method\\.matches\\(\"([^\"]+)\"\\)", local.cloud_armor_method_enforcement_exception_expression)[0], method))
      ]) && alltrue([
      for method in ["GET", "POST", "TRACE", "XDELETE", "DELETEOTHER", "patch"] :
      !can(regex(regex("request\\.method\\.matches\\(\"([^\"]+)\"\\)", local.cloud_armor_method_enforcement_exception_expression)[0], method))
    ])
    error_message = "Method matching must allow exact configured methods, not partial or case-insensitive matches."
  }

  assert {
    condition = alltrue([
      for rule in local.preconfigured_waf_rules :
      local.waf_rule_expressions[rule.name] == "evaluatePreconfiguredWaf('${rule.name}', {'sensitivity': ${rule.sensitivity}})"
      if rule.name != "methodenforcement-v33-stable"
    ])
    error_message = "All other WAF rule expressions must remain unchanged."
  }

  assert {
    condition = one([
      for rule in google_compute_security_policy.istio_gateway.rule :
      rule.match[0].expr[0].expression if rule.priority == 10050
    ]) == local.waf_rule_expressions["methodenforcement-v33-stable"]
    error_message = "The actual security policy must use the scoped expression."
  }
}

run "reject_broad_scope" {
  command = plan

  variables {
    cloud_armor_method_enforcement_exceptions = [
      {
        hostname    = "*"
        methods     = ["TRACE"]
        path_prefix = "/api"
      }
    ]
  }

  expect_failures = [var.cloud_armor_method_enforcement_exceptions]
}
