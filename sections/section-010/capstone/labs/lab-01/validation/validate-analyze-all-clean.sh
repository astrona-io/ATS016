#!/usr/bin/env bash
# PASS when analyze reports no Error and no Warning for the namespace.
set -uo pipefail
# retry-wrapped: pods that were just restarted can still be terminating, and
# proxies need a few seconds to reconnect to istiod, so retry for up to 90 s.

check() {

  NS="audit-demo"
  OUT="$(istioctl analyze -n "$NS" 2>&1)"

  if printf '%s' "$OUT" | grep -qE '^(Error|Warning) \[IST'; then
    echo "FAIL: analyze still reports Error/Warning findings in $NS:"
    printf '%s\n' "$OUT" | grep -E '^(Error|Warning) \[IST'
    return 1
  fi

  echo "PASS: no Error or Warning findings in $NS."
  return 0
}

for attempt in $(seq 1 18); do
  OUT="$(check 2>&1)" && { printf '%s\n' "$OUT"; exit 0; }
  sleep 5
done
printf '%s\n' "$OUT"
exit 1
