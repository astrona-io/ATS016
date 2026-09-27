#!/usr/bin/env bash
# PASS when a Telemetry object scopes envoy access logging to the namespace.
set -uo pipefail

NS="obscapstone-demo"
OK="$(kubectl -n "$NS" get telemetry -o json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("NONE"); raise SystemExit
for item in d.get("items",[]):
    for al in item.get("spec",{}).get("accessLogging",[]) or []:
        if al.get("disabled"): continue
        for p in al.get("providers",[]) or []:
            if p.get("name")=="envoy": print("OK"); raise SystemExit
print("NONE")')"

if [ "$OK" != "OK" ]; then
  echo "FAIL: no Telemetry object in $NS enables the 'envoy' access log provider."
  exit 1
fi
echo "PASS: access logging is declared for $NS."
exit 0
