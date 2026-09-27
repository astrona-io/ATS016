#!/usr/bin/env bash
# PASS when request metrics exist for the tester -> notification-service edge,
# so the Kiali graph has an edge to draw.
set -uo pipefail

NS="kiali-demo"

kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 5); do curl -s -o /dev/null -X POST http://notification-service/notify; done' >/dev/null 2>&1 || true
sleep 3

SERIES="$(kubectl -n "$NS" exec deploy/tester -c istio-proxy -- \
  pilot-agent request GET stats/prometheus 2>/dev/null \
  | grep '^istio_requests_total' \
  | grep 'destination_service_name="notification-service"' \
  | grep 'source_workload="tester"' | head -3)"

if [ -z "$SERIES" ]; then
  echo "FAIL: no istio_requests_total series for the tester -> notification-service edge."
  echo "      The graph needs traffic before it can draw anything."
  exit 1
fi

echo "PASS: request metrics exist for the tester -> notification-service edge."
exit 0
