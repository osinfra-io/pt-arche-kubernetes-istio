#!/usr/bin/env python3
"""Check the effective owned gateway chain, not merely EnvoyFilter manifests."""

import json
import subprocess
import time


def check_filter_order(value):
    if isinstance(value, list):
        return sum(check_filter_order(item) for item in value)
    if not isinstance(value, dict):
        return 0
    checked = 0
    filters = value.get("http_filters", [])
    strip = []
    auth = []
    guard = []
    for index, entry in enumerate(filters):
        name = entry.get("name")
        config = entry.get("typed_config", {})
        code = (
            config.get("inlineCode")
            or config.get("inline_code")
            or config.get("default_source_code", {}).get("inline_string", "")
        )
        if name == "envoy.filters.http.ext_authz":
            auth.append(index)
        if name == "envoy.filters.http.lua" and "handle:headers():remove(key)" in code:
            strip.append(index)
        if name == "envoy.filters.http.lua" and "Declared application access denied" in code:
            guard.append(index)
    if guard:
        if len(strip) != 1 or len(auth) != 1 or len(guard) != 1:
            raise ValueError("Managed listener requires exactly one strip, auth, and guard filter")
        if not strip[0] < auth[0] < guard[0]:
            raise ValueError("Managed authorization must follow stripping and successful ext_authz")
        checked += 1
    for key, child in value.items():
        if key != "http_filters":
            checked += check_filter_order(child)
    return checked


def kube(*arguments):
    result = subprocess.run(
        ["kubectl", "--context=docker-desktop", *arguments],
        capture_output=True, text=True, timeout=30,
    )
    if result.returncode:
        raise SystemExit("Owned gateway configuration query failed; inspect the local Istio component")
    return result.stdout


def main():
    owner = kube(
        "get", "configmap", "local-gateway-stack-owner", "--namespace=kube-system",
        "--output=jsonpath={.data.owner}",
    )
    if owner != "osinfra-local-gateway-stack":
        raise SystemExit("Gateway filter verification requires the owned local fixture")
    deadline = time.monotonic() + 120
    while True:
        pods = json.loads(kube(
            "get", "pods", "--namespace=istio-ingress",
            "--selector=gateway.networking.k8s.io/gateway-name=gateway", "--output=json",
        ))["items"]
        if not pods:
            raise SystemExit("No owned ingress gateway pods found")
        counts = []
        for pod in pods:
            config = json.loads(kube(
                "exec", "--namespace=istio-ingress", pod["metadata"]["name"],
                "--container=istio-proxy", "--", "pilot-agent", "request", "GET", "config_dump",
            ))
            counts.append(check_filter_order(config))
        if all(counts):
            print("Live gateway filter order verified: identity stripping -> ext_authz -> application authorization.")
            return
        if time.monotonic() >= deadline:
            raise SystemExit("Timed out waiting for application authorization in every ingress gateway")
        time.sleep(2)


if __name__ == "__main__":
    main()
