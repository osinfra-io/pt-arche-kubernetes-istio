#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_local_tools
require_docker_desktop
require_kind_nodes
require_owner
ISTIO_TEST_CONTEXT="$(resolve_istio_test_context)"
readonly ISTIO_TEST_CONTEXT
mkdir -p "${WORK_DIR}"
chmod 700 "${WORK_DIR}"

readonly GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.4.0}"
ensure_owned_resource namespace istio-ingress default
ensure_owned_resource gateway gateway istio-ingress
ensure_owned_resource namespace istio-test default
ensure_owned_resource configmap metadata-mock-content istio-test
ensure_owned_resource deployment metadata-mock istio-test
ensure_owned_resource service metadata-mock istio-test
ensure_owned_resource deployment istio-test istio-test
ensure_owned_resource service istio-test istio-test
ensure_owned_resource secret gateway-localhost-tls istio-ingress

# Gateway API is a shared prerequisite; teardown deliberately never deletes its CRDs.
kube apply --server-side \
  --filename="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
kube wait --for=condition=Established \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io \
  crd/referencegrants.gateway.networking.k8s.io \
  --timeout=120s

tofu_init "${LOCAL_DIR}/runtime" istio-runtime
assert_runtime_state_safe
ensure_owned_resource namespace istio-system default
kube apply --filename=- <<YAML
apiVersion: v1
kind: Namespace
metadata:
  labels:
    local-gateway-stack-owner: ${OWNER_VALUE}
  name: istio-system
YAML
tofu -chdir="${LOCAL_DIR}/runtime" apply -auto-approve

nodes="$(kube get nodes --output=jsonpath='{.items[*].metadata.name}')"
docker build --quiet --tag istio-test:local "${ISTIO_TEST_CONTEXT}"
docker save --output "${WORK_DIR}/istio-test.tar" istio-test:local
for node in ${nodes}; do
  docker exec -i "${node}" ctr --namespace k8s.io images import - <"${WORK_DIR}/istio-test.tar"
done

rm -f "${WORK_DIR}/gateway-localhost.key" "${WORK_DIR}/gateway-localhost.crt"
openssl req \
  -addext "subjectAltName=DNS:localhost,DNS:authentik.localhost,DNS:dev.localhost,DNS:agentgateway.localhost" \
  -keyout "${WORK_DIR}/gateway-localhost.key" \
  -new \
  -newkey rsa:2048 \
  -nodes \
  -out "${WORK_DIR}/gateway-localhost.crt" \
  -subj "/CN=dev.localhost" \
  -x509 \
  -days 1 \
  >/dev/null 2>&1
chmod 600 "${WORK_DIR}/gateway-localhost.key"

kube apply --filename="${LOCAL_DIR}/gateway.yaml"
kube create secret tls gateway-localhost-tls \
  --cert="${WORK_DIR}/gateway-localhost.crt" \
  --key="${WORK_DIR}/gateway-localhost.key" \
  --namespace=istio-ingress \
  --dry-run=client \
  --output=yaml |
  kube apply --filename=-
kube label secret gateway-localhost-tls --namespace=istio-ingress \
  "local-gateway-stack-owner=${OWNER_VALUE}" --overwrite
kube apply --filename="${LOCAL_DIR}/workload.yaml"

metadata_mock_ip="$(kube get service metadata-mock --namespace=istio-test --output=jsonpath='{.spec.clusterIP}')"
kube patch deployment istio-test \
  --namespace=istio-test \
  --type=strategic \
  --patch "{\"spec\":{\"template\":{\"spec\":{\"hostAliases\":[{\"ip\":\"${metadata_mock_ip}\",\"hostnames\":[\"metadata.google.internal\"]}]}}}}"

kube rollout status daemonset/istio-cni-node --namespace=istio-system --timeout=180s
kube rollout status daemonset/ztunnel --namespace=istio-system --timeout=180s
kube rollout status deployment/metadata-mock --namespace=istio-test --timeout=120s
kube rollout status deployment/istio-test --namespace=istio-test --timeout=180s
kube wait --for=condition=Programmed gateway/gateway --namespace=istio-ingress --timeout=120s

echo "Istio runtime is ready. Configure Authentik, then run tests/kubernetes/apply-auth.sh and tests/kubernetes/apply-routes.sh."
