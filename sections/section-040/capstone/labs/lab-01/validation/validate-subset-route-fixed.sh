#!/usr/bin/env bash
# PASS when every routed cluster exists and has healthy endpoints, and no
# invented subset selects zero pods.
set -uo pipefail

NS="dpcapstone-demo"
rc=0

ROUTED="$(istioctl proxy-config routes deploy/tester -n "$NS" -o json 2>/dev/null \
  | grep '"cluster"' | grep -E 'notification|reporting' \
  | sed 's/.*"cluster": "//; s/".*//' | sort -u)"
CLUSTERS="$(istioctl proxy-config cluster deploy/tester -n "$NS" -o json 2>/dev/null \
  | grep '"name"' | sed 's/.*"name": "//; s/".*//')"

if [ -z "$ROUTED" ]; then
  echo "FAIL: no routed clusters found for the namespace's services."
  exit 1
fi

for C in $ROUTED; do
  if ! printf '%s\n' "$CLUSTERS" | grep -qxF "$C"; then
    echo "FAIL: route names '$C', which does not exist in the proxy's cluster list."
    rc=1
    continue
  fi
  N="$(istioctl proxy-config endpoint deploy/tester -n "$NS" --cluster "$C" 2>/dev/null | grep -c HEALTHY || true)"
  if [ "$N" -lt 1 ]; then
    echo "FAIL: cluster '$C' has no HEALTHY endpoint."
    rc=1
  else
    echo "ok: $C -> $N healthy endpoint(s)."
  fi
done

BAD="$(kubectl -n "$NS" get destinationrule -o json | python3 -c '
import json,sys,subprocess
d=json.load(sys.stdin)
for item in d.get("items",[]):
    for s in item.get("spec",{}).get("subsets",[]) or []:
        labels=",".join(f"{k}={v}" for k,v in (s.get("labels") or {}).items())
        if labels: print(f"{s.get(\"name\")}|{labels}")')"
while IFS='|' read -r NAME LABELS; do
  [ -z "$NAME" ] && continue
  N="$(kubectl -n "$NS" get pods -l "$LABELS" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$N" -lt 1 ]; then
    echo "FAIL: subset '$NAME' selects '$LABELS', which matches no running pod."
    rc=1
  fi
done <<< "$BAD"

[ $rc -eq 0 ] && echo "PASS: every routed cluster exists with healthy endpoints."
exit $rc
