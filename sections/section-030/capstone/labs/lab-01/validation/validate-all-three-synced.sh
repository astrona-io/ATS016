#!/usr/bin/env bash
# PASS when all four proxies (three workloads + tester) are present and none is STALE or ERROR.
set -uo pipefail

ROWS="$(istioctl proxy-status -v 1 2>/dev/null | grep -E '\.cpcapstone-(demo|legacy)' || true)"
COUNT="$(printf '%s\n' "$ROWS" | grep -c . || true)"

rc=0
for W in orders-service payments-service billing-service tester; do
  if ! printf '%s\n' "$ROWS" | grep -q "$W"; then
    echo "FAIL: $W does not appear in istioctl proxy-status."
    rc=1
  fi
done

if printf '%s\n' "$ROWS" | grep -qE 'STALE|ERROR'; then
  echo "FAIL: at least one proxy is STALE or ERROR:"
  printf '%s\n' "$ROWS"
  rc=1
fi

[ $rc -eq 0 ] && echo "PASS: $COUNT proxies present across both namespaces, none STALE or ERROR."
exit $rc
