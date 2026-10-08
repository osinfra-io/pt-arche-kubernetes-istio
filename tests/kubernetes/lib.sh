#!/usr/bin/env bash

set -euo pipefail

readonly LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${LOCAL_DIR}/../.." && pwd)"
readonly WORK_DIR="${LOCAL_DIR}/.work"
readonly OWNER_CONFIGMAP="local-gateway-stack-owner"
readonly OWNER_NAMESPACE="kube-system"
readonly OWNER_VALUE="osinfra-local-gateway-stack"

die() {
  echo "$*" >&2
  exit 1
}

kube() {
  kubectl --context=docker-desktop "$@"
}

require_docker_desktop() {
  local current_context
  current_context="$(kubectl config current-context)"
  if [ "${current_context}" != "docker-desktop" ]; then
    die "kubectl must use docker-desktop (current context: ${current_context})"
  fi

  docker info >/dev/null
}

require_kind_nodes() {
  local nodes node cluster propagation
  nodes="$(kube get nodes --output=jsonpath='{.items[*].metadata.name}')"
  [ -n "${nodes}" ] || die "docker-desktop has no Kubernetes nodes"

  for node in ${nodes}; do
    cluster="$(docker inspect "${node}" --format '{{index .Config.Labels "io.x-k8s.kind.cluster"}}')"
    [ "${cluster}" = "desktop" ] ||
      die "Select Docker Desktop's Kind provisioner; node ${node} is not a Desktop Kind node"

    propagation="$(docker exec "${node}" findmnt --noheadings --target /var/run/netns --output PROPAGATION)"
    case "${propagation}" in
      *shared* | *slave*) ;;
      *) die "Node ${node}: /var/run/netns needs shared or slave mount propagation (found ${propagation})" ;;
    esac
  done
}

owner_value() {
  kube get configmap "${OWNER_CONFIGMAP}" --namespace="${OWNER_NAMESPACE}" \
    --output='jsonpath={.data.owner}'
}

require_owner() {
  local owner
  owner="$(owner_value 2>/dev/null)" || die "Local gateway-stack owner marker is missing"
  [ "${owner}" = "${OWNER_VALUE}" ] ||
    die "Refusing cluster owned by '${owner}', expected '${OWNER_VALUE}'"
}

assert_runtime_state_safe() {
  if kube get namespace istio-system >/dev/null 2>&1; then
    local state_file="${1:-${WORK_DIR}/istio-runtime.tfstate}"
    local state_list release helm_name chart_name address state_version release_metadata namespace_owner
    local -a releases=(base cni istiod ztunnel)

    [ -f "${state_file}" ] ||
      die "Existing Istio namespace has no local fixture state; explicit adoption is required"
    state_list="$(tofu -chdir="${LOCAL_DIR}/runtime" state list)" ||
      die "Existing Istio namespace has unreadable local fixture state; explicit adoption is required"

    if [ -z "${state_list}" ]; then
      namespace_owner="$(kube get namespace istio-system \
        --output='jsonpath={.metadata.labels.local-gateway-stack-owner}')" ||
        die "Cannot verify ownership of the retained Istio namespace"
      [ "${namespace_owner}" = "${OWNER_VALUE}" ] ||
        die "Existing Istio namespace has empty fixture state and is not fixture-owned"
      [ -z "$(helm list --kube-context=docker-desktop --namespace=istio-system --all --short)" ] ||
        die "Existing Istio namespace contains releases outside local fixture state"
      for address in deployment/istiod daemonset/istio-cni-node daemonset/ztunnel; do
        if kube get "${address}" --namespace=istio-system >/dev/null 2>&1; then
          die "Existing Istio namespace contains ${address} outside local fixture state"
        fi
      done
      return
    fi

    for release in "${releases[@]}"; do
      address="module.istio_runtime.helm_release.${release}"
      grep -Fxq "${address}" <<<"${state_list}" ||
        die "Existing Istio namespace has incomplete local fixture state; explicit adoption is required"

      helm_name="${release}"
      chart_name="${release}"
      if [ "${release}" = "cni" ]; then
        helm_name="istio-cni"
      fi

      state_version="$(tofu -chdir="${LOCAL_DIR}/runtime" state show -no-color "${address}" |
        awk '$1 == "version" && $2 == "=" { gsub(/"/, "", $3); print $3; exit }')"
      [ -n "${state_version}" ] ||
        die "Local fixture state has no recorded chart version for ${release}; explicit adoption is required"

      release_metadata="$(helm get metadata "${helm_name}" \
        --kube-context=docker-desktop \
        --namespace=istio-system \
        --output=json)" ||
        die "Cannot verify the installed Helm release ${helm_name}; explicit adoption is required"
      python3 -c '
import json
import sys

metadata = json.load(sys.stdin)
expected = {"name": sys.argv[1], "chart": sys.argv[2], "version": sys.argv[3], "status": "deployed"}
sys.exit(0 if all(metadata.get(key) == value for key, value in expected.items()) else 1)
' "${helm_name}" "${chart_name}" "${state_version}" <<<"${release_metadata}" ||
        die "Installed Helm release ${helm_name} does not match local fixture state; explicit adoption is required"
    done
  fi
}

ensure_owned_resource() {
  local kind="$1" name="$2" namespace="$3" owner
  if owner="$(kube get "${kind}" "${name}" --namespace="${namespace}" \
    --output='jsonpath={.metadata.labels.local-gateway-stack-owner}' 2>/dev/null)"; then
    [ "${owner}" = "${OWNER_VALUE}" ] ||
      die "Refusing to replace unowned ${kind} ${namespace}/${name}"
  fi
}

delete_owned_resource() {
  local kind="$1" name="$2" namespace="$3"
  ensure_owned_resource "${kind}" "${name}" "${namespace}"
  if kube get "${kind}" "${name}" --namespace="${namespace}" >/dev/null 2>&1; then
    kube delete "${kind}" "${name}" --namespace="${namespace}"
  fi
}

auth_policy_name() {
  local key="$1"
  printf 'gateway-auth-%s' "$(printf '%s-custom' "${key}" | openssl sha1 | awk '{print substr($2, 1, 8)}')"
}

ensure_auth_resources_safe() {
  local state="${1:-${WORK_DIR}/browser-auth.tfstate}"
  local key policy_name kind name
  local -a resources=(
    "envoyfilters.networking.istio.io gateway-authentik-inbound-header-strip"
  )

  for key in diagnostic agentgateway; do
    policy_name="$(auth_policy_name "${key}")"
    resources+=("authorizationpolicies.security.istio.io ${policy_name}")
  done

  for resource in "${resources[@]}"; do
    read -r kind name <<<"${resource}"
    if kube get "${kind}" "${name}" --namespace=istio-ingress >/dev/null 2>&1; then
      [ -f "${state}" ] ||
        die "Existing ${kind} istio-ingress/${name} has no fixture state; explicit adoption is required"
      ensure_owned_resource "${kind}" "${name}" istio-ingress
    fi
  done
}

require_local_tools() {
  local tool
  for tool in curl docker helm kubectl openssl python3 tofu; do
    command -v "${tool}" >/dev/null 2>&1 || die "Required command not found: ${tool}"
  done
}

route_parent_conditions() {
  local namespace="$1" route="$2" parent_name="$3" parent_namespace="$4"
  kube get httproute "${route}" --namespace="${namespace}" \
    --output="jsonpath={range .status.parents[*]}{.parentRef.name}{'|'}{.parentRef.namespace}{'|'}{.conditions[?(@.type=='Accepted')].status}{'|'}{.conditions[?(@.type=='ResolvedRefs')].status}{'\\n'}{end}" |
    awk -F'|' -v name="${parent_name}" -v ns="${parent_namespace}" -v route_ns="${namespace}" \
      '$1 == name && ($2 == ns || ($2 == "" && ns == route_ns)) { print $3 "|" $4; exit }'
}

resolve_istio_test_context() {
  if [ -n "${ISTIO_TEST_CONTEXT:-}" ]; then
    [ -f "${ISTIO_TEST_CONTEXT}/Dockerfile" ] || die "ISTIO_TEST_CONTEXT has no Dockerfile"
    printf '%s\n' "${ISTIO_TEST_CONTEXT}"
    return
  fi

  local candidate
  for candidate in \
    "${REPOSITORY_ROOT}/../pt-pneuma-istio-test" \
    "${REPOSITORY_ROOT}/../../pneuma/pt-pneuma-istio-test"; do
    if [ -f "${candidate}/Dockerfile" ]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done

  die "Could not find pt-pneuma-istio-test; set ISTIO_TEST_CONTEXT to its checkout"
}

tofu_init() {
  local root="$1" state="$2"
  export TF_DATA_DIR="${WORK_DIR}/providers/${state}"
  mkdir -p "${TF_DATA_DIR}"
  tofu -chdir="${root}" init \
    -input=false \
    -reconfigure \
    -backend-config="path=${WORK_DIR}/${state}.tfstate"
}
