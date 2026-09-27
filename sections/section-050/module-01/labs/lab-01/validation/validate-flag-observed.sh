#!/usr/bin/env bash
# PASS when the client proxy's access log shows a UT response flag.
# Sends a request first so the check does not depend on the learner's timing.
set -uo pipefail

NS="accesslog-demo"

kubectl -n "$NS" exec deploy/tester -- \
  curl -s -o /dev/null -X POST http://notification-service/notify >/dev/null 2>&1 || true
sleep 2

LOG="$(kubectl -n "$NS" logs deploy/tester -c istio-proxy --tail=40 2>/dev/null)"
if [ -z "$LOG" ]; then
  echo "FAIL: the tester proxy produced no access log lines. Is logging enabled?"
  exit 1
fi

if ! printf '%s\n' "$LOG" | grep -q ' UT '; then
  echo "FAIL: no UT response flag in the client proxy access log."
  echo "      Last lines seen:"
  printf '%s\n' "$LOG" | tail -3
  exit 1
fi

echo "PASS: a UT (upstream request timeout) flag is present in the client access log."
exit 0
