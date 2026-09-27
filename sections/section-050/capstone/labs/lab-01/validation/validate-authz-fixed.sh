#!/usr/bin/env bash
# PASS when the ALLOW policy permits exactly POST and still selects the workload.
set -uo pipefail

NS="logcapstone-demo"

if ! kubectl -n "$NS" get authorizationpolicy notification-allow >/dev/null 2>&1; then
  echo "FAIL: the AuthorizationPolicy was deleted; it must be corrected, not removed."
  exit 1
fi

ACTION="$(kubectl -n "$NS" get authorizationpolicy notification-allow -o jsonpath='{.spec.action}' 2>/dev/null)"
METHODS="$(kubectl -n "$NS" get authorizationpolicy notification-allow -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
ms=[]
for r in d.get("spec",{}).get("rules",[]) or []:
    if not r.get("to"):
        ms.append("<ANY>")
    for t in r.get("to",[]) or []:
        got=t.get("operation",{}).get("methods")
        ms += got if got else ["<ANY>"]
print(",".join(sorted(set(ms))))')"

if [ "$ACTION" != "ALLOW" ]; then
  echo "FAIL: the policy action is '$ACTION', expected ALLOW."
  exit 1
fi
if [ "$METHODS" != "POST" ]; then
  echo "FAIL: the policy permits '$METHODS', expected exactly 'POST'."
  echo "      Widening it to allow everything is not a fix."
  exit 1
fi

LABELS="$(kubectl -n "$NS" get authorizationpolicy notification-allow -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
sel=d.get("spec",{}).get("selector",{}).get("matchLabels",{})
print(",".join(f"{k}={v}" for k,v in sel.items()))')"
N="$(kubectl -n "$NS" get pods -l "$LABELS" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')"
if [ "$N" -lt 1 ]; then
  echo "FAIL: the policy selector '$LABELS' matches no running pod — it is inert."
  exit 1
fi

echo "PASS: the ALLOW policy permits exactly POST and selects $N pod(s)."
exit 0
