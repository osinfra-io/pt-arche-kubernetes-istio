#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_docker_desktop
require_owner
kube get service authentik-server --namespace=authentik >/dev/null
ensure_auth_resources_safe

mkdir -p "${WORK_DIR}"
tofu_init "${LOCAL_DIR}/browser-auth" browser-auth
tofu -chdir="${LOCAL_DIR}/browser-auth" apply -auto-approve
