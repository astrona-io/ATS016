#!/usr/bin/env bash
# PASS when ten consecutive requests carrying testing=true all reach v2.
set -uo pipefail

NS="conflict-demo"
OUT="$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST -H "testing: true" http://notification-service/notify; echo; done' 2>/dev/null | sort -u)"

LINES="$(printf '%s\n' "$OUT" | grep -c . )"
if [ "$LINES" != "1" ]; then
  echo "FAIL: the header path returned more than one distinct response — traffic is still being split."
  printf '%s\n' "$OUT"
  exit 1
fi

if ! printf '%s' "$OUT" | grep -q 'SMS'; then
  echo "FAIL: requests with testing=true returned '$OUT', expected the v2 response containing SMS."
  exit 1
fi

echo "PASS: every request carrying testing=true reached v2."
exit 0
