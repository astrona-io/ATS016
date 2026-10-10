#!/usr/bin/env bash
# PASS when ten POSTs in a row from the tester pod all return 200.
set -uo pipefail

NS="accesslog-demo"

CODES="$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -X POST http://notification-service/notify; done' 2>/dev/null)"
if [ -z "$CODES" ]; then
  echo "FAIL: could not run curl in the tester pod."
  exit 1
fi
BAD="$(printf '%s' "$CODES" | tr ' ' '\n' | grep -v '^200$' | grep -v '^$' || true)"
if [ -n "$BAD" ]; then
  echo "FAIL: not every POST returned 200. Codes: $CODES"
  echo "      Read the destination proxy's response code details to find what refuses it."
  exit 1
fi
echo "PASS: ten POSTs in a row returned 200."
exit 0
