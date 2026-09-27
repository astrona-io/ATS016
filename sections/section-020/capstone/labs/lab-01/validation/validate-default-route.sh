#!/usr/bin/env bash
# PASS when ten plain requests all reach v1.
set -uo pipefail
NS="routing-demo"
OUT="$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' 2>/dev/null | sort -u)"
N="$(printf '%s\n' "$OUT" | grep -c .)"
if [ "$N" != "1" ]; then
  echo "FAIL: the default path returned $N distinct responses — traffic is still split."
  printf '%s\n' "$OUT"; exit 1
fi
if printf '%s' "$OUT" | grep -q 'SMS'; then
  echo "FAIL: the default path returned '$OUT', expected the v1 response."
  echo "      The catch-all must send unmatched traffic to v1."; exit 1
fi
echo "PASS: every unmatched request reached v1."
exit 0
