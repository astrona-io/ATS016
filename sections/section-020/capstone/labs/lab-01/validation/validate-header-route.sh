#!/usr/bin/env bash
# PASS when ten requests carrying testing=true all reach v2.
set -uo pipefail
NS="routing-demo"
OUT="$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST -H "testing: true" http://notification-service/notify; echo; done' 2>/dev/null | sort -u)"
N="$(printf '%s\n' "$OUT" | grep -c .)"
if [ "$N" != "1" ]; then
  echo "FAIL: the header path returned $N distinct responses — traffic is still split."
  printf '%s\n' "$OUT"; exit 1
fi
if ! printf '%s' "$OUT" | grep -q 'SMS'; then
  echo "FAIL: header path returned '$OUT', expected the v2 response containing SMS."; exit 1
fi
echo "PASS: every request with testing=true reached v2."
exit 0
