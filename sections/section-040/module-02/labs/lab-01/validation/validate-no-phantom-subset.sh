#!/usr/bin/env bash
# PASS when no DestinationRule subset selects zero running pods.
# This rejects the "invent the missing subset" shortcut.
set -uo pipefail

NS="fivezerothree-demo"

if ! kubectl -n "$NS" get destinationrule notification >/dev/null 2>&1; then
  echo "FAIL: the DestinationRule was deleted; it must be kept."
  exit 1
fi

SUBSETS="$(kubectl -n "$NS" get destinationrule -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
for item in d.get("items",[]):
    for s in item.get("spec",{}).get("subsets",[]) or []:
        labels=",".join(f"{k}={v}" for k,v in (s.get("labels") or {}).items())
        print(f"{s.get(\"name\")}|{labels}")')"

rc=0
while IFS='|' read -r NAME LABELS; do
  [ -z "$NAME" ] && continue
  if [ -z "$LABELS" ]; then
    echo "ok: subset '$NAME' has no label selector (matches all pods)."
    continue
  fi
  N="$(kubectl -n "$NS" get pods -l "$LABELS" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$N" -lt 1 ]; then
    echo "FAIL: subset '$NAME' selects '$LABELS', which matches no running pod."
    echo "      Inventing a subset is not a fix — it turns NC into UH."
    rc=1
  else
    echo "ok: subset '$NAME' selects $N running pod(s)."
  fi
done <<< "$SUBSETS"

[ $rc -eq 0 ] && echo "PASS: every defined subset selects at least one running pod."
exit $rc
