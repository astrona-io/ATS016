#!/usr/bin/env bash
# PASS when reporting-service appears in proxy-status and still serves traffic.
set -uo pipefail

NS="noinject-demo"
rc=0

ROW="$(istioctl proxy-status 2>/dev/null | grep "reporting-service.*\.$NS" || true)"
if [ -z "$ROW" ]; then
  echo "FAIL: reporting-service does not appear in istioctl proxy-status."
  echo "      A container that exists is not a proxy that connected."
  rc=1
elif printf '%s' "$ROW" | grep -q 'STALE'; then
  echo "FAIL: reporting-service is present but STALE:"
  printf '%s\n' "$ROW"
  rc=1
fi

CODE="$(kubectl -n "$NS" exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}' http://reporting-service/ 2>/dev/null)"
if [ "$CODE" != "200" ]; then
  echo "FAIL: a request to reporting-service returned '$CODE', expected 200."
  echo "      Joining the mesh must not break the workload."
  rc=1
fi

[ $rc -eq 0 ] && echo "PASS: reporting-service is SYNCED in the mesh and still returns 200."
exit $rc
