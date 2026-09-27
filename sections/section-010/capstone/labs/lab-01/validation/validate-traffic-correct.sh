#!/usr/bin/env bash
# PASS when POST returns 200 and GET returns 403.
set -uo pipefail

NS="audit-demo"
rc=0

code() {
  kubectl -n "$NS" exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}' -X "$1" http://notification-service/notify 2>/dev/null
}

P="$(code POST)"; G="$(code GET)"

[ "$P" = "200" ] || { echo "FAIL: POST returned $P, expected 200."; rc=1; }
[ "$G" = "403" ] || { echo "FAIL: GET returned $G, expected 403 (the policy must be enforcing)."; rc=1; }

[ $rc -eq 0 ] && echo "PASS: POST 200, GET 403."
exit $rc
