# Kubernetes - Istio OpenTofu Module

[![OpenTofu Tests](https://img.shields.io/github/actions/workflow/status/osinfra-io/pt-arche-kubernetes-istio/test.yml?style=for-the-badge&logo=opentofu&color=FEDA15&label=OpenTofu%20Tests)](https://github.com/osinfra-io/pt-arche-kubernetes-istio/actions/workflows/test.yml) [![Dependabot](https://img.shields.io/github/actions/workflow/status/osinfra-io/pt-arche-kubernetes-istio/dependabot.yml?style=for-the-badge&logo=github&color=2088FF&label=Dependabot)](https://github.com/osinfra-io/pt-arche-kubernetes-istio/actions/workflows/dependabot.yml) [![Datadog Security Enabled](https://img.shields.io/badge/Datadog%20Security-Enabled-632CA6?style=for-the-badge&logo=datadog)](https://app.datadoghq.com/security/code-security/repositories?repository_id=pt-arche-kubernetes-istio)

## Repository Description

OpenTofu **example** module that deploys the Istio service mesh on GKE using the official Helm charts (base and istiod). It optionally provisions a Kubernetes Gateway API ingress gateway — the `Gateway` resource is reconciled by istiod, which auto-provisions the `gateway-istio` data plane — backed by a global static IP, Cloud Armor WAF/DDoS protection with adaptive rate limiting, and an SSL policy for TLS termination. Routing is expressed with `HTTPRoute` resources. Multi-cluster ingress (MCI) and multi-cluster service (MCS) resources are supported for cross-cluster traffic, and cert-manager integration is included for mTLS via an intermediate CA.

## 🔩 Usage

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

The `tests/docker` fixture exercises browser authentication end to end with Docker Desktop Kubernetes, the Authentik Docker fixture from [`pt-arche-kubernetes-authentik`](https://github.com/osinfra-io/pt-arche-kubernetes-authentik), and the [`pt-pneuma-istio-test`](https://github.com/osinfra-io/pt-pneuma-istio-test) application.

The test verifies:

- an unauthenticated `/istio-test` request is redirected through the Authentik embedded outpost;
- Google authenticates the user and Authentik provisions the user into the `all` group;
- the Authentik application policy binding permits members of `all`;
- `/outpost.goauthentik.io` callbacks return through the Istio gateway;
- the authenticated request reaches the `istio-test` workload.

Prerequisites:

- Docker Desktop Kubernetes enabled;
- `kubectl`, `docker`, `curl`, `openssl`, and OpenTofu available;
- the `pt-arche-kubernetes-authentik`, `pt-arche-kubernetes-istio`, and `pt-pneuma-istio-test` repositories checked out;
- a Google OAuth web client allowing `http://localhost:9000/source/oauth/callback/google/`.

Start and configure Authentik from the `pt-arche-kubernetes-authentik` repository:

```bash
export TF_VAR_google_oauth_client_id="<google-client-id>"
export TF_VAR_google_oauth_client_secret="<google-client-secret>"

docker compose --file tests/docker/compose.yml up --detach
tests/docker/wait-for-authentik.sh
tofu -chdir=tests/docker/regional/config init
tofu -chdir=tests/docker/regional/config apply
```

The Authentik test OpenTofu creates the `Development` application and `https://dev.localhost` proxy provider, assigns the provider to the embedded outpost, and binds the `all` group. Do not create these objects with Authentik API calls or through the UI.

Switch to the Docker Desktop cluster, then run the Istio fixture from this repository:

```bash
kubectl config use-context docker-desktop

export ISTIO_TEST_CONTEXT="../../pneuma/pt-pneuma-istio-test"
tests/docker/setup.sh
```

The setup script downloads the module's pinned Istio version, installs Gateway API and Istio, builds and imports the local `istio-test` image, generates a one-day TLS certificate for `dev.localhost`, and deploys the gateway authentication resources.

Open:

```none
https://dev.localhost/istio-test/health/basic
```

Accept the expected temporary self-signed certificate warning, select Google on the Authentik login page, and authenticate with an allowed Workspace account. A successful flow returns the `istio-test` health response.

Remove the Kubernetes fixture:

```bash
tests/docker/teardown.sh
```

Remove the Authentik fixture from its repository:

```bash
docker compose --file tests/docker/compose.yml down --volumes
```

## 📦 Release

To release a new version, simply push a new tag to the repository. The tag should be in the format `vX.Y.Z` where `X`, `Y`, and `Z` are integers.

```none
git tag vX.Y.Z
git push origin vX.Y.Z
```
