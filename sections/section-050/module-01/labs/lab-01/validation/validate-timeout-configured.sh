#!/usr/bin/env bash
# PASS when the VirtualService sets a 2s timeout AND still injects the delay.
set -uo pipefail

NS="accesslog-demo"

RESULT="$(kubectl -n "$NS" get virtualservice -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
timeout=None; delay=None
for item in d.get("items",[]):
    spec=item.get("spec",{})
    if not any(h.split(".")[0]=="notification-service" for h in spec.get("hosts",[]) or []):
        continue
    for r in spec.get("http",[]) or []:
        if r.get("timeout"): timeout=r["timeout"]
        f=(r.get("fault") or {}).get("delay") or {}
        if f.get("fixedDelay"): delay=f["fixedDelay"]
print((timeout or "NONE") + " " + (delay or "NONE"))')"

set -- $RESULT
TIMEOUT="${1:-NONE}"; DELAY="${2:-NONE}"

if [ "$TIMEOUT" != "2s" ]; then
  echo "FAIL: the route timeout is '$TIMEOUT', expected '2s'."
  exit 1
fi
if [ "$DELAY" = "NONE" ]; then
  echo "FAIL: the injected delay was removed. Bound it with a timeout; do not delete it."
  exit 1
fi

echo "PASS: timeout is 2s and the $DELAY delay is still injected."
exit 0
