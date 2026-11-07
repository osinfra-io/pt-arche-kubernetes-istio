# Test
# https://opentofu.org/docs/cli/commands/test

# Mock Providers
# https://opentofu.org/docs/cli/commands/test/#the-mock_provider-blocks

mock_provider "google" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}

mock_provider "terraform" {
  mock_data "terraform_remote_state" {
    defaults = {
      outputs = {
        gateway_mci_global_address = "192.0.2.0" # https://www.rfc-editor.org/rfc/rfc5737#section-3
      }
    }
  }
}

run "default" {
  command = apply

  module {
    source = "./tests/fixtures/default"
  }

  variables {
    gateway_dns = {
      "mock-environment.mock-subdomain.mock-domain" = {
        managed_zone = "mock-environment-mock-subdomain-mock-domain"
        project      = "mock-dns-project"
      }
    }
  }
}

run "retained_certificate" {
  command = plan

  module {
    source = "./tests/fixtures/default"
  }

  variables {
    gateway_dns = {
      "a.mock-domain" = {
        managed_zone = "mock-zone"
        project      = "mock-dns-project"
      }
      "b.mock-domain" = {
        managed_zone = "mock-zone"
        project      = "mock-dns-project"
      }
    }

    gateway_retained_domain_sets = [["a.mock-domain"]]
  }

  assert {
    condition     = length(module.test.gateway_mci_ssl_certificate_names) == 2
    error_message = "The current and retained domain sets must each get their own certificate."
  }
}

run "detached_retained_certificate" {
  command = plan

  module {
    source = "./tests/fixtures/default"
  }

  variables {
    gateway_attach_retained_certificates = false
    gateway_dns = {
      "a.mock-domain" = {
        managed_zone = "mock-zone"
        project      = "mock-dns-project"
      }
      "b.mock-domain" = {
        managed_zone = "mock-zone"
        project      = "mock-dns-project"
      }
    }

    gateway_retained_domain_sets = [["a.mock-domain"]]
  }

  assert {
    condition     = length(module.test.gateway_mci_ssl_certificate_names) == 1
    error_message = "Only the current certificate may be attached once retained certificates are detached."
  }
}

run "default_regional" {
  command = apply

  module {
    source = "./tests/fixtures/default/regional"
  }

  variables {
    gateway_dns = {
      "mock-region-a.mock-environment.mock-subdomain.mock-domain" = {
        managed_zone = "mock-environment-mock-subdomain-mock-domain"
        project      = "mock-dns-project"
      }
    }
  }
}

variables {
  project = "mock-project"
}

run "ztunnel_access_logging" {
  command = plan

  module {
    source = "./regional/runtime"
  }

  variables {
    cluster_name            = "mock-cluster"
    cni_cpu_requests        = "100m"
    cni_memory_requests     = "128Mi"
    cni_platform            = ""
    environment             = "sandbox"
    image_hub               = "docker.io/istio"
    network                 = "mock-network"
    pilot_autoscale_max     = 1
    pilot_autoscale_min     = 1
    pilot_cpu_limits        = "500m"
    pilot_cpu_requests      = "100m"
    pilot_memory_limits     = "512Mi"
    pilot_memory_requests   = "128Mi"
    pilot_replica_count     = 1
    proxy_cpu_limits        = "500m"
    proxy_cpu_requests      = "100m"
    proxy_memory_limits     = "256Mi"
    proxy_memory_requests   = "128Mi"
    ztunnel_cpu_limits      = "500m"
    ztunnel_cpu_requests    = "100m"
    ztunnel_memory_limits   = "512Mi"
    ztunnel_memory_requests = "128Mi"
  }

  assert {
    condition     = yamldecode(helm_release.ztunnel.values[0]).logLevel == "info,access=warn"
    error_message = "ztunnel must suppress successful access logs while retaining access warnings/errors and other INFO logs."
  }
}
