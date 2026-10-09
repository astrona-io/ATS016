#!/usr/bin/env bash
# PASS when all four proxies (three workloads + tester) are present and none is STALE or ERROR.
# Pods that were just restarted take a few seconds to reconnect to istiod, so
# the check retries for up to 90 seconds before it fails.
set -uo pipefail

check_proxies() {
  ROWS="$(istioctl proxy-status -v 1 2>/dev/null | grep -E '\.cpcapstone-(demo|legacy)' || true)"
  MISSING=""
  for W in orders-service payments-service billing-service tester; do
    printf '%s\n' "$ROWS" | grep -q "$W" || MISSING="$MISSING $W"
  done
  BAD="$(printf '%s\n' "$ROWS" | grep -E 'STALE|ERROR' || true)"
  [ -z "$MISSING" ] && [ -z "$BAD" ]
}

for attempt in $(seq 1 18); do
  check_proxies && break
  sleep 5
done

if [ -n "$MISSING" ] || [ -n "$BAD" ]; then
  for W in $MISSING; do
    echo "FAIL: $W does not appear in istioctl proxy-status."
  done
  [ -n "$BAD" ] && echo "FAIL: at least one proxy is STALE or ERROR."
  echo "      istioctl proxy-status -v 1 printed:"
  istioctl proxy-status -v 1 2>&1 | sed 's/^/        /'
  exit 1
fi

COUNT="$(printf '%s\n' "$ROWS" | grep -c .)"
echo "PASS: $COUNT proxies present across both namespaces, none STALE or ERROR."
exit 0
