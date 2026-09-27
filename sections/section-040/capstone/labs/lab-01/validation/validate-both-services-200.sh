#!/usr/bin/env bash
# PASS when both services answer 200 from the tester pod.
set -uo pipefail

NS="dpcapstone-demo"
rc=0

N="$(kubectl -n "$NS" exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}' -X POST http://notification-service/notify 2>/dev/null)"
R="$(kubectl -n "$NS" exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}' http://reporting-service/status 2>/dev/null)"

[ "$N" = "200" ] || { echo "FAIL: notification-service returned $N, expected 200."; rc=1; }
[ "$R" = "200" ] || { echo "FAIL: reporting-service returned $R, expected 200."; rc=1; }

[ $rc -eq 0 ] && echo "PASS: both services return 200."
exit $rc
