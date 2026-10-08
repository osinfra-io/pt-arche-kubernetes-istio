#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_docker_desktop
require_owner

for namespace in istio-system istio-ingress istio-test; do
  ensure_owned_resource namespace "${namespace}" default
done

if [ -f "${WORK_DIR}/browser-auth.tfstate" ]; then
  tofu_init "${LOCAL_DIR}/browser-auth" browser-auth
  tofu -chdir="${LOCAL_DIR}/browser-auth" destroy -auto-approve \
    -lock-timeout=60s
fi

delete_owned_resource httproute authentik authentik
delete_owned_resource httproute authentik-google-callback authentik
delete_owned_resource httproute authentik-outpost authentik
delete_owned_resource httproute istio-test istio-test
delete_owned_resource deployment metadata-mock istio-test
delete_owned_resource deployment istio-test istio-test
delete_owned_resource service metadata-mock istio-test
delete_owned_resource service istio-test istio-test
delete_owned_resource configmap metadata-mock-content istio-test
delete_owned_resource gateway gateway istio-ingress
delete_owned_resource secret gateway-localhost-tls istio-ingress

if [ -f "${WORK_DIR}/istio-runtime.tfstate" ]; then
  tofu_init "${LOCAL_DIR}/runtime" istio-runtime
  assert_runtime_state_safe
  tofu -chdir="${LOCAL_DIR}/runtime" destroy -auto-approve \
    -lock-timeout=60s
fi

for namespace in istio-test istio-ingress istio-system; do
  delete_owned_resource namespace "${namespace}" default
done

echo "Owned Istio resources and namespaces removed. Shared CRDs and the owner marker were retained."
