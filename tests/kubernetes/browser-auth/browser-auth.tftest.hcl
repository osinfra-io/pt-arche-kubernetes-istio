# Mocked local browser-auth policy checks
# https://opentofu.org/docs/cli/commands/test/

mock_provider "kubernetes" {}

run "diagnostic_and_agentgateway_browser_policies" {
  command = apply

  module {
    source = "./"
  }

  assert {
    condition     = contains(keys(module.browser_auth.custom_authorization_policy_manifests), "diagnostic") && contains(keys(module.browser_auth.custom_authorization_policy_manifests), "agentgateway")
    error_message = "Both the diagnostic and agentgateway hosts must receive shared-rendered browser policies."
  }

  assert {
    condition     = contains(module.browser_auth.custom_authorization_policy_manifests.agentgateway.spec.rules[0].to[0].operation.hosts, "agentgateway.localhost") && length(module.browser_auth.custom_authorization_policy_manifests.agentgateway.spec.rules[0].to[0].operation.paths) == 1 && contains(module.browser_auth.custom_authorization_policy_manifests.agentgateway.spec.rules[0].to[0].operation.paths, "/*")
    error_message = "The agentgateway policy must protect the complete diagnostic route and admin UI host."
  }

  assert {
    condition     = contains(module.browser_auth.custom_authorization_policy_manifests.agentgateway.spec.rules[0].to[0].operation.notPaths, "/agentgateway-test/health") && contains(module.browser_auth.custom_authorization_policy_manifests.agentgateway.spec.rules[0].to[0].operation.notPaths, "/agentgateway-test/metadata/*")
    error_message = "Only the agentgateway health and metadata endpoints may bypass browser authentication."
  }
}
