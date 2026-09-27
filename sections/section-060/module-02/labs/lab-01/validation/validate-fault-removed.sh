#!/usr/bin/env bash
# PASS when no fault injection remains and traffic succeeds.
set -uo pipefail

NS="metrics-demo"

FAULTS="$(kubectl -n "$NS" get virtualservice -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
out=[]
for item in d.get("items",[]):
    name=item["metadata"]["name"]
    for idx,r in enumerate(item.get("spec",{}).get("http",[]) or []):
        if r.get("fault"):
            out.append(f"{name} http[{idx}]")
print("\n".join(out))')"

if [ -n "$FAULTS" ]; then
  echo "FAIL: fault injection is still configured:"
  printf '  %s\n' "$FAULTS"
  exit 1
fi

CODES="$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -X POST http://notification-service/notify; done' 2>/dev/null)"
if printf '%s' "$CODES" | tr ' ' '\n' | grep -v '^$' | grep -qv '^200$'; then
  echo "FAIL: not every request returned 200. Codes: $CODES"
  exit 1
fi

echo "PASS: no fault injection remains and ten requests returned 200."
exit 0
