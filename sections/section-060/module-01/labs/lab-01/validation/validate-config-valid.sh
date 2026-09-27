#!/usr/bin/env bash
# PASS when analyze is clean AND a route to notification-service still exists.
set -uo pipefail

NS="kiali-demo"

OUT="$(istioctl analyze -n "$NS" 2>&1)"
if printf '%s' "$OUT" | grep -qE '^(Error|Warning) \[IST'; then
  echo "FAIL: istioctl analyze still reports findings in $NS:"
  printf '%s\n' "$OUT"
  exit 1
fi

ROUTED="$(kubectl -n "$NS" get virtualservice -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
n=0
for i in d.get("items",[]):
    spec=i.get("spec",{})
    if any(h.split(".")[0]=="notification-service" for h in spec.get("hosts",[]) or []):
        n+=1
print(n)')"

if [ "$ROUTED" = "0" ]; then
  echo "FAIL: analyze is clean but nothing routes to notification-service."
  echo "      Deleting every routing object is not a fix."
  exit 1
fi

echo "PASS: analyze reports no findings and $ROUTED VirtualService routes the host."
exit 0
