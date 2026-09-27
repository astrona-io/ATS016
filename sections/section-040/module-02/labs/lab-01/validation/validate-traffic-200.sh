#!/usr/bin/env bash
# PASS when ten consecutive POSTs return 200.
set -uo pipefail

NS="fivezerothree-demo"
CODES="$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -X POST http://notification-service/notify; done' 2>/dev/null)"

if [ -z "$CODES" ]; then
  echo "FAIL: could not run curl in the tester pod."
  exit 1
fi
if printf '%s' "$CODES" | tr ' ' '\n' | grep -v '^$' | grep -qv '^200$'; then
  echo "FAIL: not every request returned 200. Codes: $CODES"
  exit 1
fi

echo "PASS: ten consecutive POSTs returned 200."
exit 0
