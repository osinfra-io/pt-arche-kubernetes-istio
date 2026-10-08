#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

test_dir="$(mktemp -d)"
runtime_test_state="${test_dir}/runtime.tfstate"
auth_test_state="${test_dir}/browser-auth.tfstate"
trap 'rm -f "${runtime_test_state}"; rmdir "${test_dir}"' EXIT

for release in base cni istiod ztunnel; do
  grep -Fq "from = helm_release.${release}" "${REPOSITORY_ROOT}/regional/moved.tofu"
  grep -Fq "to   = module.runtime.helm_release.${release}" "${REPOSITORY_ROOT}/regional/moved.tofu"
done

mock_context="docker-desktop"
mock_owner=""
mock_resource_owner=""
mock_resource=""
mock_istio_namespace=false
mock_empty_state=false
mock_missing_state_release=""
mock_mismatched_helm_release=""
mock_parent_conditions=""
mock_istio_namespace_owner=""
mock_istio_releases=""
docker() {
  [ "${1:-}" = "info" ]
}

kubectl() {
  if [ "${1:-}" = "--context=docker-desktop" ]; then
    shift
  fi

  case "${1:-} ${2:-}" in
    "config current-context")
      printf '%s\n' "${mock_context}"
      ;;
    "get configmap")
      [ "${3:-}" = "${OWNER_CONFIGMAP}" ] || return 1
      [ -n "${mock_owner}" ] || return 1
      printf '%s\n' "${mock_owner}"
      ;;
    "get namespace")
      [ "${3:-}" = "istio-system" ] && [ "${mock_istio_namespace}" = true ] || return 1
      if [[ "${*:4}" == *"--output="* ]]; then
        printf '%s\n' "${mock_istio_namespace_owner}"
      fi
      ;;
    "get httproute")
      printf '%s\n' "${mock_parent_conditions}"
      ;;
    "get "*)
      [ "${2:-} ${3:-}" = "${mock_resource}" ] || return 1
      if [[ "${*:4}" == *"--output="* ]]; then
        [ -n "${mock_resource_owner}" ] || return 1
        printf '%s\n' "${mock_resource_owner}"
      fi
      ;;
    *)
      echo "Unexpected mocked kubectl command: $*" >&2
      return 2
      ;;
  esac
}

tofu() {
  local release
  case "${2:-} ${3:-}" in
    "state list")
      [ "${mock_empty_state}" = false ] || return 0
      for release in base cni istiod ztunnel; do
        [ "${release}" = "${mock_missing_state_release}" ] ||
          printf 'module.istio_runtime.helm_release.%s\n' "${release}"
      done
      ;;
    "state show")
      printf 'version = "1.31.0-rc.0"\n'
      ;;
    *)
      echo "Unexpected mocked tofu command: $*" >&2
      return 2
      ;;
  esac
}

helm() {
  if [ "${1:-}" = "list" ]; then
    printf '%s' "${mock_istio_releases}"
    return
  fi
  local release="${3:-}"
  local chart="${release}"
  local chart_version="1.31.0-rc.0"
  [ "${release}" != "istio-cni" ] || chart="cni"
  [ "${release}" = "${mock_mismatched_helm_release}" ] && chart_version="1.31.1"
  printf '{"name":"%s","status":"deployed","chart":"%s","version":"%s"}\n' \
    "${release}" "${chart}" "${chart_version}"
}

assert_fails() {
  if ( "$@" ) >/dev/null 2>&1; then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi
}

mock_context="other-context"
assert_fails require_docker_desktop
mock_context="docker-desktop"

assert_fails require_owner
mock_owner="another-stack"
assert_fails require_owner
mock_owner="${OWNER_VALUE}"
require_owner

mock_resource="gateway gateway"
mock_resource_owner="another-stack"
assert_fails ensure_owned_resource gateway gateway istio-ingress
mock_resource_owner="${OWNER_VALUE}"
ensure_owned_resource gateway gateway istio-ingress

mock_resource=""
ensure_auth_resources_safe "${auth_test_state}"
mock_resource="authorizationpolicies.security.istio.io $(auth_policy_name diagnostic)"
assert_fails ensure_auth_resources_safe "${auth_test_state}"
mock_resource="authorizationpolicies.security.istio.io $(auth_policy_name agentgateway)"
assert_fails ensure_auth_resources_safe "${auth_test_state}"

mock_parent_conditions=$'gateway|other-namespace|True|True\nother-gateway|istio-ingress|True|True\ngateway|istio-ingress|True|False'
[ "$(route_parent_conditions authentik authentik gateway istio-ingress)" = "True|False" ]
mock_parent_conditions=$'gateway|other-namespace|True|False\ngateway|istio-ingress|False|True'
[ "$(route_parent_conditions authentik authentik gateway istio-ingress)" = "False|True" ]
mock_parent_conditions="gateway||True|True"
[ -z "$(route_parent_conditions authentik authentik gateway istio-ingress)" ]
[ "$(route_parent_conditions istio-ingress same-namespace gateway istio-ingress)" = "True|True" ]
mock_parent_conditions="gateway|istio-ingress|True|True"
[ "$(route_parent_conditions authentik authentik gateway istio-ingress)" = "True|True" ]

mock_istio_namespace=true
assert_fails assert_runtime_state_safe "${runtime_test_state}"
: >"${runtime_test_state}"
mock_empty_state=true
assert_fails assert_runtime_state_safe "${runtime_test_state}"
mock_istio_namespace_owner="${OWNER_VALUE}"
assert_runtime_state_safe "${runtime_test_state}"
mock_istio_releases="unrelated-release"
assert_fails assert_runtime_state_safe "${runtime_test_state}"
mock_istio_releases=""
mock_resource="deployment/istiod --namespace=istio-system"
assert_fails assert_runtime_state_safe "${runtime_test_state}"
mock_resource=""
mock_istio_namespace_owner=""
mock_empty_state=false
mock_missing_state_release="cni"
assert_fails assert_runtime_state_safe "${runtime_test_state}"
mock_missing_state_release=""
mock_mismatched_helm_release="ztunnel"
assert_fails assert_runtime_state_safe "${runtime_test_state}"
mock_mismatched_helm_release=""
assert_runtime_state_safe "${runtime_test_state}"

(
  calls=""
  tofu_init() { calls+="init "; }
  assert_runtime_state_safe() { calls+="state-check "; }
  ensure_owned_resource() {
    [ "$*" = "namespace istio-system default" ] || exit 1
    calls+="owner-check "
  }
  kube() {
    [ "$*" = "apply --filename=-" ] || exit 1
    manifest="$(cat)" || exit 1
    grep -Fq "local-gateway-stack-owner: ${OWNER_VALUE}" <<<"${manifest}" || exit 1
    grep -Fq "name: istio-system" <<<"${manifest}" || exit 1
    calls+="owned-namespace "
  }
  tofu() {
    [ "${calls}" = "init state-check owner-check owned-namespace " ] || exit 1
    return 1
  }
  # Exercise namespace ownership even when the subsequent runtime apply fails.
  setup_runtime="$(sed -n '/^tofu_init .* istio-runtime$/,/^tofu .* apply -auto-approve$/p' "${LOCAL_DIR}/setup.sh")"
  [ -n "${setup_runtime}" ]
  if source /dev/stdin <<<"${setup_runtime}"; then
    echo "Expected simulated runtime apply to fail" >&2
    exit 1
  fi
  [ "${calls}" = "init state-check owner-check owned-namespace " ]
)

echo "Local fixture ownership tests passed."
