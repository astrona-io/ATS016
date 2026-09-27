#!/usr/bin/env bash
# PASS when exactly one VirtualService claims notification-service on the mesh gateway.
set -uo pipefail

NS="conflict-demo"

COUNT="$(kubectl -n "$NS" get virtualservice -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
n=0
for i in d.get("items",[]):
    spec=i.get("spec",{})
    hosts=spec.get("hosts",[]) or []
    gws=spec.get("gateways",[]) or ["mesh"]
    if any(h.split(".")[0]=="notification-service" for h in hosts) and "mesh" in gws:
        n+=1
print(n)')"

if [ "$COUNT" != "1" ]; then
  echo "FAIL: $COUNT VirtualService objects claim notification-service on the mesh gateway; expected exactly 1."
  kubectl -n "$NS" get virtualservice -o custom-columns='NAME:.metadata.name,HOSTS:.spec.hosts,GATEWAYS:.spec.gateways'
  exit 1
fi

if istioctl analyze -n "$NS" 2>&1 | grep -q 'IST0109'; then
  echo "FAIL: istioctl analyze still reports IST0109 (conflicting hosts)."
  exit 1
fi

echo "PASS: exactly one VirtualService owns the host, and IST0109 is gone."
exit 0
