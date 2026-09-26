# Kubernetes - Istio OpenTofu Module

[![OpenTofu Tests](https://img.shields.io/github/actions/workflow/status/osinfra-io/pt-arche-kubernetes-istio/test.yml?style=for-the-badge&logo=opentofu&color=FEDA15&label=OpenTofu%20Tests)](https://github.com/osinfra-io/pt-arche-kubernetes-istio/actions/workflows/test.yml) [![Dependabot](https://img.shields.io/github/actions/workflow/status/osinfra-io/pt-arche-kubernetes-istio/dependabot.yml?style=for-the-badge&logo=github&color=2088FF&label=Dependabot)](https://github.com/osinfra-io/pt-arche-kubernetes-istio/actions/workflows/dependabot.yml) [![Datadog Security Enabled](https://img.shields.io/badge/Datadog%20Security-Enabled-632CA6?style=for-the-badge&logo=datadog)](https://app.datadoghq.com/security/code-security/repositories?repository_id=pt-arche-kubernetes-istio)

## Repository Description

Reusable OpenTofu child module that deploys the Istio service mesh on GKE in ambient mode, using the official Helm charts for the ambient data plane (`istio-cni` and `ztunnel`) with `istiod` as the control plane. It optionally provisions a Kubernetes Gateway API ingress gateway — the `Gateway` resource is reconciled by istiod, which auto-provisions the `gateway-istio` data plane — backed by a global static IP, Cloud Armor WAF/DDoS protection with adaptive rate limiting, and an SSL policy for TLS termination. Routing is expressed with `HTTPRoute` resources. Multi-cluster ingress (MCI) and multi-cluster service (MCS) resources are supported for cross-cluster traffic, and cert-manager integration is included for mTLS via an intermediate CA.

Every cluster is assigned its own logical Istio network (derived from `cluster_prefix`/region/zone/environment) and gets a dedicated ambient east-west `Gateway` (`gatewayClassName: istio-east-west`, HBONE-only on port `15008`, internal GKE load balancer). This follows [upstream Istio's supported ambient multicluster path](https://istio.io/latest/docs/ambient/install/multicluster/) — same-network ambient multicluster is documented as untested and may be broken — and requires no per-team configuration: newly onboarded teams and clusters get a working east-west gateway automatically. Services that should be reachable from other clusters must be labeled `istio.io/global: "true"` in the consuming repo.

## 🔩 Usage

### Module interfaces

| Source path | Purpose | Interface |
| --- | --- | --- |
| Repository root | Creates fleet-level ingress IP, managed certificate, DNS, Cloud Armor policy, and TLS policy when this project owns multi-cluster ingress. | [`variables.tofu`](variables.tofu) · [`outputs.tofu`](outputs.tofu) |
| `//regional` | Deploys ambient Istio, CNI, ztunnel, per-cluster east-west gateway, and optional ingress/MCI/MCS resources. | [`regional/variables.tofu`](regional/variables.tofu) · [`regional/outputs.tofu`](regional/outputs.tofu) |
| `//regional/manifests` | Creates mesh security policy, destination rules, and `HTTPRoute` resources for application routes and optional regional failover. | [`regional/manifests/variables.tofu`](regional/manifests/variables.tofu) |

The regional module always deploys the ambient control/data plane and an internal HBONE east-west gateway; public ingress is disabled unless `enable_istio_gateway` is true. It requires the shared cert-manager root certificate and private key, which are written to a Kubernetes Secret and must be protected in state and at rest. The current Istio chart default is a release candidate because the corresponding GA charts were not published in the configured chart repository. The root Cloud Armor policy blocks preconfigured WAF matches, rate-limits all traffic at 500 requests per minute, and defaults unmatched traffic to allow; test explicit allow rules and WAF exclusions carefully. Gateways, global addresses, Cloud Armor, managed certificates, DNS, and cross-region traffic can incur GCP costs.

> [!TIP]
> You can check the [tests/fixtures](tests/fixtures) directory for example configurations. These fixtures set up the system for testing by providing all the necessary initial code, thus creating good examples on which to base your configurations.

Google project services must be enabled before using this module. As a best practice, these should be defined in the [pt-arche-google-project](https://github.com/osinfra-io/pt-arche-google-project) module. The following services are required:

- `compute.googleapis.com`
- `dns.googleapis.com`

## 🛠️ Tools

- [helm](https://github.com/helm/helm)
- [osinfra-pre-commit-hooks](https://github.com/osinfra-io/pt-techne-pre-commit-hooks)
- [pre-commit](https://github.com/pre-commit/pre-commit)

## 📋 Skills and Knowledge

Links to documentation and other resources required to develop and iterate in this repository successfully.

- [ambient mesh](https://istio.io/latest/docs/ambient)
- [cloud armor](https://cloud.google.com/armor/docs)
- [cloud dns](https://cloud.google.com/dns/docs)
- [google-managed certificates](https://cloud.google.com/load-balancing/docs/ssl-certificates/google-managed-certs)
- [istio](https://istio.io/latest/docs)
  - [istio on gke](https://istio.io/latest/docs/setup/platform-setup/gke)

## 🔍 Tests

All tests are [mocked](https://opentofu.org/docs/cli/commands/test/#the-mock_provider-blocks) allowing us to test the module without creating infrastructure or requiring credentials. The trade-offs are acceptable in favor of speed and simplicity. In an OpenTofu test, a mocked provider or resource will generate fake data for all computed attributes that would normally be provided by the underlying provider APIs.

```none
tofu init
```

```none
tofu test
```

### Local browser authentication

The `tests/docker` fixture exercises Istio and Authentik browser authentication with Docker Desktop Kubernetes and [`pt-pneuma-istio-test`](https://github.com/osinfra-io/pt-pneuma-istio-test). Install the [`platform-grouping` plugin](https://github.com/osinfra-io/pt-ai-plugins/tree/main/plugins/platform-grouping) and ask Copilot CLI to use the `test-istio-authentik-locally` skill instead of running the fixture manually. The skill discovers the related repositories, runs the setup and verification checks, diagnoses failures, supports optional Google OAuth testing, and performs cleanup when requested.

```text
Use the test-istio-authentik-locally skill to test this checkout.
```

## 📦 Release

To release a new version, simply push a new tag to the repository. The tag should be in the format `vX.Y.Z` where `X`, `Y`, and `Z` are integers.

```none
git tag vX.Y.Z
git push origin vX.Y.Z
```
