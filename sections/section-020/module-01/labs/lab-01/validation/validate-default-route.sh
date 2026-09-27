#!/usr/bin/env bash
# PASS when ten consecutive requests with no header all reach v1.
set -uo pipefail

NS="conflict-demo"
OUT="$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' 2>/dev/null | sort -u)"

LINES="$(printf '%s\n' "$OUT" | grep -c . )"
if [ "$LINES" != "1" ]; then
  echo "FAIL: the default path returned more than one distinct response — traffic is still being split."
  printf '%s\n' "$OUT"
  exit 1
fi

if printf '%s' "$OUT" | grep -q 'SMS'; then
  echo "FAIL: requests without the header returned '$OUT', expected the v1 response."
  echo "      The catch-all route must send unmatched traffic to v1."
  exit 1
fi

echo "PASS: every request without the header reached v1."
exit 0
