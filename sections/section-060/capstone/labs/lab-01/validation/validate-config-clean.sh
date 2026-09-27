#!/usr/bin/env bash
# PASS when analyze is clean, one object owns the host, and no phantom subset exists.
set -uo pipefail

NS="obscapstone-demo"

OUT="$(istioctl analyze -n "$NS" 2>&1)"
if printf '%s' "$OUT" | grep -qE '^(Error|Warning) \[IST'; then
  echo "FAIL: istioctl analyze still reports findings in $NS:"
  printf '%s\n' "$OUT" | grep -E '^(Error|Warning) \[IST'
  exit 1
fi

COUNT="$(kubectl -n "$NS" get virtualservice -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
n=0
for i in d.get("items",[]):
    spec=i.get("spec",{})
    gws=spec.get("gateways",[]) or ["mesh"]
    if any(h.split(".")[0]=="notification-service" for h in spec.get("hosts",[]) or []) and "mesh" in gws:
        n+=1
print(n)')"
if [ "$COUNT" != "1" ]; then
  echo "FAIL: $COUNT VirtualService objects claim the host on the mesh gateway; expected 1."
  exit 1
fi

BAD="$(kubectl -n "$NS" get destinationrule -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
for item in d.get("items",[]):
    for s in item.get("spec",{}).get("subsets",[]) or []:
        labels=",".join(f"{k}={v}" for k,v in (s.get("labels") or {}).items())
        if labels: print(f"{s.get(\"name\")}|{labels}")')"
rc=0
while IFS='|' read -r NAME LABELS; do
  [ -z "$NAME" ] && continue
  N="$(kubectl -n "$NS" get pods -l "$LABELS" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$N" -lt 1 ]; then
    echo "FAIL: subset '$NAME' selects '$LABELS', which matches no running pod."
    rc=1
  fi
done <<< "$BAD"

[ $rc -eq 0 ] && echo "PASS: analyze clean, one host owner, no phantom subsets."
exit $rc
