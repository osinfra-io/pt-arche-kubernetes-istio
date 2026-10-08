# Browser authentication configuration
# https://github.com/osinfra-io/pt-pneuma

module "browser_auth" {
  source = "../../../../../pneuma/pt-pneuma/regional/istio/gateway-auth"

  extension_provider_name = "authentik"
  gateway_name            = "gateway"
  gateway_namespace       = "istio-ingress"
  outpost_namespace       = "authentik"
  outpost_path_prefix     = "/outpost.goauthentik.io/auth/envoy"
  outpost_service_name    = "authentik-server"
  outpost_service_port    = 80

  policies = {
    agentgateway = {
      host         = "agentgateway.localhost"
      path         = "/"
      public_paths = ["/agentgateway-test/health", "/agentgateway-test/metadata/*"]
    }

    diagnostic = {
      host         = "dev.localhost"
      path         = "/istio-test"
      public_paths = ["/istio-test/health", "/istio-test/metadata/*"]
    }
  }
}

# Kubernetes Manifest Resource
# https://search.opentofu.org/provider/hashicorp/kubernetes/latest/docs/resources/manifest

resource "kubernetes_manifest" "browser_policies" {
  for_each = module.browser_auth.custom_authorization_policy_manifests

  manifest = local.browser_policy_manifests[each.key]
}

resource "kubernetes_manifest" "inbound_header_strip_filter" {
  manifest = local.inbound_header_strip_filter_manifest
}
