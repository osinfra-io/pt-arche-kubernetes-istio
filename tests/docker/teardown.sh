#!/usr/bin/env bash

set -euo pipefail

readonly GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.4.0}"
readonly ISTIO_VERSION="${ISTIO_VERSION:-1.30.3}"

kubectl delete namespace authentik istio-ingress istio-test --ignore-not-found

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

curl --fail --location --silent --show-error \
  "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-${istio_architecture}.tar.gz" |
  tar --extract --gzip --directory="${temporary_directory}"

"${temporary_directory}/istio-${ISTIO_VERSION}/bin/istioctl" uninstall --purge --skip-confirmation

kubectl delete \
  --filename "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" \
  --ignore-not-found
