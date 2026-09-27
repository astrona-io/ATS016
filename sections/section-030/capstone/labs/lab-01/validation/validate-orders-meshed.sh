#!/usr/bin/env bash
# PASS when orders-service carries a sidecar and the opt-out is gone.
set -uo pipefail

NS="cpcapstone-demo"

VAL="$(kubectl -n "$NS" get deploy orders-service \
  -o jsonpath='{.spec.template.metadata.labels.sidecar\.istio\.io/inject}' 2>/dev/null)"
if [ "$VAL" = "false" ]; then
  echo "FAIL: orders-service still carries the pod-template opt-out."
  exit 1
fi

C="$(kubectl -n "$NS" get pods -l app=orders-service \
  -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null)"
if ! printf '%s' "$C" | grep -q 'istio-proxy'; then
  echo "FAIL: orders-service containers are '$C' — no istio-proxy."
  exit 1
fi

echo "PASS: orders-service is injected and the opt-out is removed."
exit 0
