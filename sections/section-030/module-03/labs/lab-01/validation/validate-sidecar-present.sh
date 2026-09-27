#!/usr/bin/env bash
# PASS when reporting-service pods carry the istio-proxy container.
set -uo pipefail

NS="noinject-demo"
CONTAINERS="$(kubectl -n "$NS" get pods -l app=reporting-service \
  -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null)"

if [ -z "$CONTAINERS" ]; then
  echo "FAIL: no reporting-service pod found in $NS."
  exit 1
fi
if ! printf '%s' "$CONTAINERS" | grep -q 'istio-proxy'; then
  echo "FAIL: reporting-service containers are '$CONTAINERS' — no istio-proxy."
  exit 1
fi

echo "PASS: reporting-service carries the istio-proxy sidecar."
exit 0
