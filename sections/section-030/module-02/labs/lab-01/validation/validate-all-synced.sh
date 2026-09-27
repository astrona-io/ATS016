#!/usr/bin/env bash
# PASS when every workload in the namespace appears in proxy-status and no row is STALE.
set -uo pipefail

NS="proxysync-demo"

PODS="$(kubectl -n "$NS" get pods --field-selector=status.phase=Running -o name | wc -l | tr -d ' ')"
ROWS="$(istioctl proxy-status 2>/dev/null | grep "\.$NS" || true)"
COUNT="$(printf '%s\n' "$ROWS" | grep -c . || true)"

if [ "$COUNT" -lt "$PODS" ]; then
  echo "FAIL: $PODS running pods in $NS but only $COUNT appear in proxy-status."
  printf '%s\n' "$ROWS"
  exit 1
fi

if printf '%s\n' "$ROWS" | grep -q 'STALE'; then
  echo "FAIL: at least one proxy is STALE:"
  printf '%s\n' "$ROWS"
  exit 1
fi

echo "PASS: all $COUNT proxies in $NS are present and none is STALE."
exit 0
