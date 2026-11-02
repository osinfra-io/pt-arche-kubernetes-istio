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
