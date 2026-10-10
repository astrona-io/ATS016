#!/usr/bin/env bash
# PASS when no VirtualService in the namespace has an HTTP rule with both a
# redirect and a route. Removing the object and correcting it are both acceptable.
set -uo pipefail

NS="cphealth-demo"

BAD="$(kubectl -n "$NS" get virtualservice -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
bad=[]
for item in d.get("items",[]):
    name=item["metadata"]["name"]
    for idx,rule in enumerate(item.get("spec",{}).get("http",[]) or []):
        if rule.get("redirect") and rule.get("route"):
            bad.append(f"{name} http[{idx}] has both redirect and route")
print("\n".join(bad))')"

if [ -n "$BAD" ]; then
  echo "FAIL: invalid route rule(s) still present in $NS:"
  printf '  %s\n' "$BAD"
  exit 1
fi

if istioctl analyze -n "$NS" 2>&1 | grep -qE '^Error \[IST'; then
  echo "FAIL: istioctl analyze still reports an Error in $NS:"
  istioctl analyze -n "$NS" 2>&1 | grep -E '^Error \[IST'
  exit 1
fi

echo "PASS: no invalid route rule remains, and analyze reports no Errors."
exit 0
