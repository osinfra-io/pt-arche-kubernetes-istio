#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.4.0}"
readonly ISTIO_VERSION="${ISTIO_VERSION:-1.30.3}"

# Locate the pt-pneuma-istio-test checkout so contributors don't have to know the exact relative
# path between repos. Honors an explicit ISTIO_TEST_CONTEXT override first, then checks common
# checkout layouts (plain sibling clone, and the aggregated platform-group workspace), and
# finally falls back to a shallow search from the repository root.
resolve_istio_test_context() {
  if [ -n "${ISTIO_TEST_CONTEXT:-}" ]; then
    echo "${ISTIO_TEST_CONTEXT}"
    return 0
  fi

  local repository_root candidate
  repository_root="$(cd "${SCRIPT_DIR}/../.." && pwd)"

  for candidate in \
    "${repository_root}/../pt-pneuma-istio-test" \
    "${repository_root}/../../pneuma/pt-pneuma-istio-test"; do
    if [ -f "${candidate}/Dockerfile" ]; then
      echo "${candidate}"
      return 0
    fi
  done

  candidate="$(find "${repository_root}/.." -maxdepth 3 -type d -name pt-pneuma-istio-test -print -quit 2>/dev/null || true)"
  if [ -n "${candidate}" ] && [ -f "${candidate}/Dockerfile" ]; then
    echo "${candidate}"
    return 0
  fi

  return 1
}

if ! ISTIO_TEST_CONTEXT="$(resolve_istio_test_context)"; then
  echo "Could not locate the pt-pneuma-istio-test checkout; set ISTIO_TEST_CONTEXT to its path" >&2
  exit 1
fi
readonly ISTIO_TEST_CONTEXT

if [ "$(kubectl config current-context)" != "docker-desktop" ]; then
  echo "kubectl must use the docker-desktop context" >&2
  exit 1
fi

docker build --quiet --tag istio-test:local "${ISTIO_TEST_CONTEXT}"
docker save istio-test:local |
  docker exec -i desktop-control-plane ctr --namespace k8s.io images import -

kubectl apply --filename "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

temporary_directory="$(mktemp --directory)"
trap 'rm -rf "${temporary_directory}"' EXIT

case "$(uname -m)" in
  aarch64 | arm64)
    istio_architecture="arm64"
    ;;
  x86_64 | amd64)
    istio_architecture="amd64"
    ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

case "$(uname -s)" in
  Darwin)
    istio_platform="osx"
    ;;
  Linux)
    istio_platform="linux"
    ;;
  *)
    echo "Unsupported operating system: $(uname -s)" >&2
    exit 1
    ;;
esac

curl --fail --location --silent --show-error \
  "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-${istio_platform}-${istio_architecture}.tar.gz" |
  tar --extract --gzip --directory="${temporary_directory}"

readonly ISTIOCTL="${temporary_directory}/istio-${ISTIO_VERSION}/bin/istioctl"

"${ISTIOCTL}" install --skip-confirmation \
  --set profile=minimal \
  --set meshConfig.extensionProviders[0].name=authentik \
  --set meshConfig.extensionProviders[0].envoyExtAuthzHttp.service=authentik-server.authentik.svc.cluster.local \
  --set meshConfig.extensionProviders[0].envoyExtAuthzHttp.port=9000 \
  --set meshConfig.extensionProviders[0].envoyExtAuthzHttp.pathPrefix=/outpost.goauthentik.io/auth/envoy \
  --set meshConfig.extensionProviders[0].envoyExtAuthzHttp.failOpen=false \
  --set meshConfig.extensionProviders[0].envoyExtAuthzHttp.includeRequestHeadersInCheck[0]=cookie \
  --set meshConfig.extensionProviders[0].envoyExtAuthzHttp.headersToUpstreamOnAllow[0]=set-cookie \
  --set meshConfig.extensionProviders[0].envoyExtAuthzHttp.headersToUpstreamOnAllow[1]=x-authentik-* \
  --set meshConfig.extensionProviders[0].envoyExtAuthzHttp.headersToDownstreamOnAllow[0]=cookie \
  --set meshConfig.extensionProviders[0].envoyExtAuthzHttp.headersToDownstreamOnDeny[0]=content-type \
  --set meshConfig.extensionProviders[0].envoyExtAuthzHttp.headersToDownstreamOnDeny[1]=set-cookie

authentik_host_ip="$(
  kubectl run authentik-host-lookup \
    --image=busybox:1.37 \
    --restart=Never \
    --rm \
    --quiet \
    --stdin \
    --command -- \
    nslookup host.docker.internal |
    awk '/^Address: / { address = $2 } END { print address }'
)"

sed "s/AUTHENTIK_HOST_IP/${authentik_host_ip}/" "${SCRIPT_DIR}/authentik-endpoint.yaml" |
  kubectl apply --filename -

kubectl create namespace istio-ingress --dry-run=client --output=yaml |
  kubectl apply --filename -

openssl req \
  -addext "subjectAltName=DNS:dev.localhost" \
  -keyout "${temporary_directory}/tls.key" \
  -new \
  -newkey rsa:2048 \
  -nodes \
  -out "${temporary_directory}/tls.crt" \
  -subj "/CN=dev.localhost" \
  -x509 \
  -days 1 \
  >/dev/null 2>&1

kubectl create secret tls gateway-localhost-tls \
  --cert="${temporary_directory}/tls.crt" \
  --key="${temporary_directory}/tls.key" \
  --namespace=istio-ingress \
  --dry-run=client \
  --output=yaml |
  kubectl apply --filename -

kubectl apply --filename "${SCRIPT_DIR}/istio-auth.yaml"
metadata_mock_ip="$(kubectl get service metadata-mock --namespace=istio-test --output=jsonpath='{.spec.clusterIP}')"
kubectl patch deployment istio-test \
  --namespace=istio-test \
  --type=strategic \
  --patch "{\"spec\":{\"template\":{\"spec\":{\"hostAliases\":[{\"ip\":\"${metadata_mock_ip}\",\"hostnames\":[\"metadata.google.internal\"]}]}}}}"
kubectl rollout status deployment/metadata-mock --namespace=istio-test --timeout=120s
kubectl wait --for=condition=Programmed gateway/gateway --namespace=istio-ingress --timeout=120s
kubectl rollout status deployment/istio-test --namespace=istio-test --timeout=180s

echo "Setup complete. Open https://dev.localhost/istio-test/auth and accept the temporary certificate."
