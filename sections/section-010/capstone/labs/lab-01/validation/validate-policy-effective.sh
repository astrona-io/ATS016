#!/usr/bin/env bash
# PASS when the AuthorizationPolicy selects the workload and permits only POST.
set -uo pipefail

NS="audit-demo"

if ! kubectl -n "$NS" get authorizationpolicy notification-post-only >/dev/null 2>&1; then
  echo "FAIL: the AuthorizationPolicy was deleted; it must be made effective, not removed."
  exit 1
fi

SEL="$(kubectl -n "$NS" get authorizationpolicy notification-post-only \
  -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null)"
METHODS="$(kubectl -n "$NS" get authorizationpolicy notification-post-only -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
ms=[]
for r in d.get("spec",{}).get("rules",[]) or []:
    for t in r.get("to",[]) or []:
        ms += t.get("operation",{}).get("methods",[]) or []
print(",".join(sorted(set(ms))))')"

LABELS="$(printf '%s' "$SEL" | python3 -c '
import json,sys
raw=sys.stdin.read().strip()
try: d=json.loads(raw)
except Exception: print(""); raise SystemExit
print(",".join(f"{k}={v}" for k,v in d.items()))')"

if [ -z "$LABELS" ]; then
  echo "FAIL: the policy has no selector labels."
  exit 1
fi

N="$(kubectl -n "$NS" get pods -l "$LABELS" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')"
if [ "$N" -lt 1 ]; then
  echo "FAIL: the policy selector '$LABELS' matches no running pod — it is inert."
  exit 1
fi

if [ "$METHODS" != "POST" ]; then
  echo "FAIL: the policy permits methods '$METHODS', expected exactly 'POST'."
  exit 1
fi

echo "PASS: the policy selects $N pod(s) and permits only POST."
exit 0
