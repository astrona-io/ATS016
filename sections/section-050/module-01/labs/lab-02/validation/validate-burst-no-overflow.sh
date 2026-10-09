#!/usr/bin/env bash
# PASS when the DestinationRule keeps its connection pool and a burst of
# 20 POSTs at the same time all return 200 (no 503 UO from the client proxy).
set -uo pipefail

NS="accesslog-demo"

if ! kubectl -n "$NS" get destinationrule notification >/dev/null 2>&1; then
  echo "FAIL: the DestinationRule notification was deleted. Raise its limits instead."
  exit 1
fi
POOL="$(kubectl -n "$NS" get destinationrule notification \
  -o jsonpath='{.spec.trafficPolicy.connectionPool.tcp.maxConnections}' 2>/dev/null)"
if [ -z "$POOL" ]; then
  echo "FAIL: connectionPool.tcp.maxConnections was removed. Keep a limit, just a larger one."
  exit 1
fi

CODES="$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code}\n" -X POST http://notification-service/notify & done; wait' 2>/dev/null)"
if [ -z "$CODES" ]; then
  echo "FAIL: could not run curl in the tester pod."
  exit 1
fi
TOTAL="$(printf '%s\n' "$CODES" | grep -c '^[0-9]')"
OK="$(printf '%s\n' "$CODES" | grep -c '^200$')"
if [ "$OK" -ne 20 ]; then
  echo "FAIL: $OK of $TOTAL POSTs sent at the same time returned 200."
  echo "      Codes: $(printf '%s\n' "$CODES" | sort | uniq -c | tr '\n' ' ')"
  exit 1
fi
echo "PASS: a burst of 20 POSTs at the same time all returned 200."
exit 0
