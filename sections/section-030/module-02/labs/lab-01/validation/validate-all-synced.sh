#!/usr/bin/env bash
# PASS when every workload in the namespace appears in proxy-status and no row is STALE or ERROR.
set -uo pipefail
# retry-wrapped: pods that were just restarted can still be terminating, and
# proxies need a few seconds to reconnect to istiod, so retry for up to 90 s.

check() {

  NS="proxysync-demo"

  PODS="$(kubectl -n "$NS" get pods --field-selector=status.phase=Running -o name | wc -l | tr -d ' ')"
  ROWS="$(istioctl proxy-status -v 1 2>/dev/null | grep "\.$NS" || true)"
  COUNT="$(printf '%s\n' "$ROWS" | grep -c . || true)"

  if [ "$COUNT" -lt "$PODS" ]; then
    echo "FAIL: $PODS running pods in $NS but only $COUNT appear in proxy-status."
    printf '%s\n' "$ROWS"
    return 1
  fi

  if printf '%s\n' "$ROWS" | grep -qE 'STALE|ERROR'; then
    echo "FAIL: at least one proxy is STALE or ERROR:"
    printf '%s\n' "$ROWS"
    return 1
  fi

  echo "PASS: all $COUNT proxies in $NS are present and none is STALE or ERROR."
  return 0
}

for attempt in $(seq 1 18); do
  OUT="$(check 2>&1)" && { printf '%s\n' "$OUT"; exit 0; }
  sleep 5
done
printf '%s\n' "$OUT"
exit 1
