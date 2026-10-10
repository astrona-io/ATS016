#!/usr/bin/env bash
# PASS when the DENY policy block-delete still exists and DELETE returns 403.
# Rejects the shortcut of deleting the policy or changing it to ALLOW.
set -uo pipefail

NS="accesslog-demo"

if ! kubectl -n "$NS" get authorizationpolicy block-delete >/dev/null 2>&1; then
  echo "FAIL: the AuthorizationPolicy block-delete was deleted. Correct it instead."
  exit 1
fi
ACTION="$(kubectl -n "$NS" get authorizationpolicy block-delete -o jsonpath='{.spec.action}' 2>/dev/null)"
if [ "$ACTION" != "DENY" ]; then
  echo "FAIL: block-delete has action '$ACTION', expected DENY."
  exit 1
fi
CODE="$(kubectl -n "$NS" exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}' -X DELETE http://notification-service/notify 2>/dev/null)"
if [ "$CODE" != "403" ]; then
  echo "FAIL: a DELETE returned '$CODE', expected 403. The policy must still block DELETE."
  exit 1
fi
echo "PASS: block-delete is a DENY policy and DELETE returns 403."
exit 0
