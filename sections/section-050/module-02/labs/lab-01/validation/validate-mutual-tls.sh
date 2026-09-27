#!/usr/bin/env bash
# PASS when the destination proxy reports mutual_tls for observed traffic.
set -uo pipefail

NS="mtlsfail-demo"

for i in 1 2 3; do
  kubectl -n "$NS" exec deploy/tester -- \
    curl -s -o /dev/null -X POST http://notification-service/notify >/dev/null 2>&1 || true
done
sleep 2

POLICIES="$(kubectl -n "$NS" exec deploy/notification-service-v1 -c istio-proxy -- \
  pilot-agent request GET stats/prometheus 2>/dev/null \
  | grep istio_requests_total | grep -o 'connection_security_policy="[^"]*"' | sort -u)"

if [ -z "$POLICIES" ]; then
  echo "FAIL: the destination proxy reports no istio_requests_total series."
  exit 1
fi

if ! printf '%s\n' "$POLICIES" | grep -q 'mutual_tls'; then
  echo "FAIL: the destination reports $POLICIES — expected mutual_tls."
  echo "      Working traffic and encrypted traffic are different claims."
  exit 1
fi

if printf '%s\n' "$POLICIES" | grep -q 'connection_security_policy="none"'; then
  echo "FAIL: some traffic is still plaintext (connection_security_policy=none)."
  exit 1
fi

echo "PASS: the destination reports connection_security_policy=mutual_tls."
exit 0
