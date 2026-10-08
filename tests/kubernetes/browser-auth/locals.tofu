# Local Values
# https://opentofu.org/docs/language/values/locals

locals {
  browser_policy_manifests = {
    for key, manifest in module.browser_auth.custom_authorization_policy_manifests :
    key => merge(manifest, {
      metadata = merge(manifest.metadata, {
        labels = merge(try(manifest.metadata.labels, {}), local.owner_labels)
      })
    })
  }

  inbound_header_strip_filter_manifest = merge(module.browser_auth.inbound_header_strip_filter_manifest, {
    metadata = merge(module.browser_auth.inbound_header_strip_filter_manifest.metadata, {
      labels = merge(
        try(module.browser_auth.inbound_header_strip_filter_manifest.metadata.labels, {}),
        local.owner_labels
      )
    })
  })

  owner_labels = {
    "local-gateway-stack-owner" = "osinfra-local-gateway-stack"
  }
}
