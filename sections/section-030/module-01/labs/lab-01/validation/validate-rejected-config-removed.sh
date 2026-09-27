#!/usr/bin/env bash
# PASS when no VirtualService in the namespace has route weights that fail to
# sum to 100. Removing the object and correcting it are both acceptable.
set -uo pipefail

NS="cphealth-demo"

BAD="$(kubectl -n "$NS" get virtualservice -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
bad=[]
for item in d.get("items",[]):
    name=item["metadata"]["name"]
    for idx,route in enumerate(item.get("spec",{}).get("http",[]) or []):
        dests=route.get("route",[]) or []
        weights=[x.get("weight") for x in dests]
        if len(dests) > 1 or any(w is not None for w in weights):
            total=sum(w or 0 for w in weights)
            if total != 100:
                bad.append(f"{name} http[{idx}] weights sum to {total}")
print("\n".join(bad))')"

if [ -n "$BAD" ]; then
  echo "FAIL: invalid weighted route(s) still present in $NS:"
  printf '  %s\n' "$BAD"
  exit 1
fi

if istioctl analyze -n "$NS" 2>&1 | grep -qE '^Error \[IST'; then
  echo "FAIL: istioctl analyze still reports an Error in $NS:"
  istioctl analyze -n "$NS" 2>&1 | grep -E '^Error \[IST'
  exit 1
fi

echo "PASS: no route weights fail to sum to 100, and analyze reports no Errors."
exit 0
