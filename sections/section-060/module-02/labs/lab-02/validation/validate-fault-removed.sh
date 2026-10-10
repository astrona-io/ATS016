#!/usr/bin/env bash
# PASS when the VirtualService `notification` still routes notification-service,
# no fault injection remains, and ten requests from each client return 200.
#
# Deleting the VirtualService is not the fix the task asks for: the route stays,
# only the fault goes.
set -uo pipefail
NS="callers-demo"
VS_JSON="$(kubectl -n "$NS" get virtualservice notification -o json 2>/dev/null)"
if [ -z "$VS_JSON" ]; then
  echo "FAIL: the VirtualService 'notification' was deleted. Remove the fault, keep the route."
  exit 1
fi
RESULT="$(printf '%s' "$VS_JSON" | python3 -c '
import json,sys
d=json.load(sys.stdin)
spec=d.get("spec",{})
hosts=[h.split(".")[0] for h in spec.get("hosts",[]) or []]
http=spec.get("http",[]) or []
if "notification-service" not in hosts or not http:
    print("NOROUTE"); raise SystemExit
if any(r.get("fault") for r in http):
    print("FAULT"); raise SystemExit
print("OK")')"
case "$RESULT" in
  NOROUTE) echo "FAIL: 'notification' no longer routes notification-service."; exit 1 ;;
  FAULT)   echo "FAIL: 'notification' still has a fault block."; exit 1 ;;
esac
rc=0
for CLIENT in reports-client orders-client; do
  CODES="$(kubectl -n "$NS" exec "deploy/$CLIENT" -- sh -c \
    'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -X POST http://notification-service/notify; done' 2>/dev/null)"
  if [ -z "$CODES" ] || printf '%s' "$CODES" | tr ' ' '\n' | grep -v '^$' | grep -qv '^200$'; then
    echo "FAIL: not every request from $CLIENT returned 200. Codes: ${CODES:-none}"
    rc=1
  else
    echo "ok: ten requests from $CLIENT returned 200."
  fi
done
[ $rc -eq 0 ] && echo "PASS: the route remains, the fault is gone, and both clients get 200."
exit $rc
