#!/usr/bin/env bash
# PASS when every proxy in the namespace is SYNCED (checked with `istioctl proxy-status -v 1`,
# because since Istio 1.27 the short form shows no per-type sync state) and traffic returns 200.
set -uo pipefail
# retry-wrapped: pods that were just restarted can still be terminating, and
# proxies need a few seconds to reconnect to istiod, so retry for up to 90 s.

check() {

  NS="cphealth-demo"
  rc=0

  ROWS="$(istioctl proxy-status -v 1 2>/dev/null | grep "\.$NS" || true)"
  if [ -z "$ROWS" ]; then
    echo "FAIL: no proxies from $NS appear in istioctl proxy-status."
    return 1
  fi

  COUNT="$(printf '%s\n' "$ROWS" | wc -l | tr -d ' ')"
  if [ "$COUNT" -lt 2 ]; then
    echo "FAIL: expected at least 2 proxies from $NS in proxy-status, found $COUNT."
    rc=1
  fi

  if printf '%s\n' "$ROWS" | grep -qE 'STALE|ERROR'; then
    echo "FAIL: at least one proxy is STALE or ERROR:"
    printf '%s\n' "$ROWS"
    rc=1
  fi

  CODE="$(kubectl -n "$NS" exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}' -X POST http://notification-service/notify 2>/dev/null)"
  if [ "$CODE" != "200" ]; then
    echo "FAIL: a POST to notification-service returned $CODE, expected 200."
    rc=1
  fi

  [ $rc -eq 0 ] && echo "PASS: $COUNT proxies SYNCED and traffic returns 200."
  return $rc
}

for attempt in $(seq 1 18); do
  OUT="$(check 2>&1)" && { printf '%s\n' "$OUT"; exit 0; }
  sleep 5
done
printf '%s\n' "$OUT"
exit 1
