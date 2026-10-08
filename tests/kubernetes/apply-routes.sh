#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_docker_desktop
require_owner
kube get service authentik-server --namespace=authentik >/dev/null
ensure_owned_resource httproute authentik authentik
ensure_owned_resource httproute authentik-google-callback authentik
ensure_owned_resource httproute authentik-outpost authentik
ensure_owned_resource httproute istio-test istio-test

kube apply --filename="${LOCAL_DIR}/routes.yaml"
kube wait --for=condition=Programmed gateway/gateway --namespace=istio-ingress --timeout=120s
