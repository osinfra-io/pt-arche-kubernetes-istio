#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_local_tools
require_docker_desktop
require_owner

python3 "${LOCAL_DIR}/verify-auth-filters.py"

kube wait --for=condition=Programmed gateway/gateway --namespace=istio-ingress --timeout=120s
kube rollout status deployment/istio-test --namespace=istio-test --timeout=180s

for app in istio-test metadata-mock; do
  pods="$(kube get pods --namespace=istio-test --selector="app=${app}" \
    --output=jsonpath='{.items[*].metadata.name}')"
  [ -n "${pods}" ] || die "No pods found for ${app}"

  for pod in ${pods}; do
    kube wait --namespace=istio-test "pod/${pod}" \
      --for=jsonpath='{.metadata.annotations.ambient\.istio\.io/redirection}'=enabled \
      --timeout=120s
    containers="$(kube get pod "${pod}" --namespace=istio-test \
      --output=jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}')"
    [[ " ${containers} " != *" istio-proxy "* ]] ||
      die "Pod ${pod} has an injected istio-proxy; this fixture must use ambient mode only"
  done
done

for route in authentik authentik-google-callback authentik-outpost istio-test; do
  namespace=istio-test
  case "${route}" in authentik*) namespace=authentik ;; esac
  conditions="$(route_parent_conditions "${namespace}" "${route}" gateway istio-ingress)"
  [ "${conditions}" = "True|True" ] ||
    die "HTTPRoute ${namespace}/${route} is not Accepted and ResolvedRefs on istio-ingress/gateway"
done

for path in /istio-test/health /istio-test/metadata/cluster-name; do
  response_headers="${WORK_DIR}/response-headers"
  status="$(curl --noproxy '*' --connect-timeout 5 --max-time 15 --insecure \
    --silent --show-error --dump-header "${response_headers}" \
    --output /dev/null --write-out '%{http_code}' "https://dev.localhost${path}")"
  [ "${status}" = "200" ] || die "Expected 200 for dev.localhost${path}, got ${status}"
  if grep -qi '^location:[[:space:]]*[^[:space:]]' "${response_headers}"; then
    die "Public diagnostic dev.localhost${path} unexpectedly returned a Location header"
  fi
done

url=https://dev.localhost/istio-test/auth
response_headers="${WORK_DIR}/response-headers"
status="$(curl --noproxy '*' --connect-timeout 5 --max-time 15 --insecure --silent --show-error \
  --dump-header "${response_headers}" --output /dev/null --write-out '%{http_code}' "${url}")"
location="$(grep -i '^location:' "${response_headers}" | tail -1 | tr -d '\r' | cut -d ' ' -f2-)"
[ "${status}" = "302" ] || die "Expected 302 for protected URL ${url}, got ${status}"
[[ "${location}" == https://authentik.localhost/application/o/authorize/* ]] ||
  die "Protected URL ${url} did not redirect to Authentik"

for path in /ui/ /api /config_dump; do
  for identity in anonymous forged; do
    headers=()
    if [ "${identity}" = forged ]; then
      headers=(
        --header 'X-authentik-osinfra-google-email: member@example.com'
        --header 'X-authentik-osinfra-google-email: other@example.com'
        --header 'X-authentik-groups: pt-pneuma: agentgateway Admins'
      )
    fi
    url="https://agentgateway.localhost${path}"
    status="$(curl --noproxy '*' --connect-timeout 5 --max-time 15 --insecure \
      --silent --show-error --dump-header "${response_headers}" --output /dev/null \
      --write-out '%{http_code}' "${headers[@]}" "${url}")"
    [ "${status}" = "302" ] ||
      die "Expected Authentik redirect for ${identity} admin request ${url}, got ${status}"
    grep -qi '^location: https://authentik.localhost/application/o/authorize/' "${response_headers}" ||
      die "Admin request ${url} did not redirect to Authentik"
  done
done

curl --noproxy '*' --connect-timeout 5 --max-time 15 --insecure --silent --show-error --fail \
  https://authentik.localhost/-/health/live/ >/dev/null
echo "Automated HTTP checks passed. Complete Google sign-in manually at https://dev.localhost/istio-test/auth."
