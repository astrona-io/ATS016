#!/usr/bin/env bash
# PASS when reporting-service appears in proxy-status and still serves traffic.
set -uo pipefail
# retry-wrapped: pods that were just restarted can still be terminating, and
# proxies need a few seconds to reconnect to istiod, so retry for up to 90 s.

check() {

  NS="noinject-demo"
  rc=0

  ROW="$(istioctl proxy-status -v 1 2>/dev/null | grep "reporting-service.*\.$NS" || true)"
  if [ -z "$ROW" ]; then
    echo "FAIL: reporting-service does not appear in istioctl proxy-status."
    echo "      A container that exists is not a proxy that connected."
    rc=1
  elif printf '%s' "$ROW" | grep -qE 'STALE|ERROR'; then
    echo "FAIL: reporting-service is present but STALE or ERROR:"
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
  return $rc
}

for attempt in $(seq 1 18); do
  OUT="$(check 2>&1)" && { printf '%s\n' "$OUT"; exit 0; }
  sleep 5
done
printf '%s\n' "$OUT"
exit 1
