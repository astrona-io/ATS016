#!/usr/bin/env bash
# PASS when every subset named by a VirtualService route is defined by the
# DestinationRule AND selects at least one running pod.
#
# This is the check that rejects the "invent the missing subset" shortcut.
set -uo pipefail

NS="analyze-demo"
HOST="notification-service"

ROUTED="$(kubectl -n "$NS" get virtualservice -o json \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)
out=set()
for item in d.get("items",[]):
    for route in item.get("spec",{}).get("http",[]):
        for dest in route.get("route",[]):
            s=dest.get("destination",{}).get("subset")
            if s: out.add(s)
print("\n".join(sorted(out)))')"

if [ -z "$ROUTED" ]; then
  echo "FAIL: no VirtualService route names a subset. Expected a route to an existing subset."
  exit 1
fi

DR_JSON="$(kubectl -n "$NS" get destinationrule -o json)"
if [ -z "$DR_JSON" ]; then
  echo "FAIL: no DestinationRule found in $NS (it must not be deleted)."
  exit 1
fi

rc=0
for SUB in $ROUTED; do
  LABELS="$(printf '%s' "$DR_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for item in d.get('items',[]):
    if item.get('spec',{}).get('host','').split('.')[0] != '$HOST':
        continue
    for s in item.get('spec',{}).get('subsets',[]) or []:
        if s.get('name')=='$SUB':
            print(','.join(f'{k}={v}' for k,v in (s.get('labels') or {}).items()))
            break")"

  if [ -z "$LABELS" ]; then
    echo "FAIL: route names subset '$SUB' but no DestinationRule for $HOST defines it."
    rc=1
    continue
  fi

  COUNT="$(kubectl -n "$NS" get pods -l "$LABELS" --field-selector=status.phase=Running \
    -o name 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$COUNT" -lt 1 ]; then
    echo "FAIL: subset '$SUB' selects labels '$LABELS', which match no running pod."
    echo "      Routing to a subset with no endpoints is not a fix."
    rc=1
    continue
  fi
  echo "ok: subset '$SUB' is defined and selects $COUNT running pod(s)."
done

[ $rc -eq 0 ] && echo "PASS: every routed subset exists and has running pods."
exit $rc
