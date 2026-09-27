#!/usr/bin/env bash
# PASS when a POST from the tester pod returns 200.
set -uo pipefail

NS="mtlsfail-demo"
CODE="$(kubectl -n "$NS" exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}' -X POST http://notification-service/notify 2>/dev/null)"

if [ "$CODE" != "200" ]; then
  echo "FAIL: a POST to notification-service returned '$CODE', expected 200."
  exit 1
fi
echo "PASS: traffic returns 200."
exit 0
