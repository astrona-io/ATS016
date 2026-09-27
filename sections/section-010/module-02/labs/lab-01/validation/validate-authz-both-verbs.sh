#!/usr/bin/env bash
# PASS when GET and POST both return 200 and DELETE still returns 403.
# The DELETE check is what distinguishes "widened the policy" from "removed it".
set -uo pipefail

NS="describe-demo"
URL="http://notification-service/notify"
rc=0

code() {
  kubectl -n "$NS" exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$URL" 2>/dev/null
}

for M in GET POST; do
  C="$(code "$M")"
  if [ "$C" != "200" ]; then
    echo "FAIL: $M returned $C, expected 200."
    rc=1
  else
    echo "ok: $M returned 200."
  fi
done

C="$(code DELETE)"
if [ "$C" != "403" ]; then
  echo "FAIL: DELETE returned $C, expected 403."
  echo "      The policy must still refuse methods it does not name."
  rc=1
else
  echo "ok: DELETE still returns 403."
fi

if ! kubectl -n "$NS" get authorizationpolicy notification-post-only >/dev/null 2>&1; then
  echo "FAIL: the AuthorizationPolicy was deleted rather than widened."
  rc=1
fi

[ $rc -eq 0 ] && echo "PASS: GET and POST permitted, DELETE still denied."
exit $rc
