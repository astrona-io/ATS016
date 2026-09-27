#!/usr/bin/env bash
# PASS when no route weights fail to sum to 100 and payments-service answers.
set -uo pipefail

NS="cpcapstone-demo"

BAD="$(kubectl -n "$NS" get virtualservice -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
bad=[]
for item in d.get("items",[]):
    name=item["metadata"]["name"]
    for idx,route in enumerate(item.get("spec",{}).get("http",[]) or []):
        dests=route.get("route",[]) or []
        weights=[x.get("weight") for x in dests]
        if len(dests) > 1 or any(w is not None for w in weights):
            total=sum(w or 0 for w in weights)
            if total != 100:
                bad.append(f"{name} http[{idx}] weights sum to {total}")
print("\n".join(bad))')"

if [ -n "$BAD" ]; then
  echo "FAIL: invalid weighted route(s) still present:"
  printf '  %s\n' "$BAD"
  exit 1
fi

CODE="$(kubectl -n "$NS" exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}' http://payments-service/get 2>/dev/null)"
if [ "$CODE" != "200" ]; then
  echo "FAIL: a request to payments-service returned '$CODE', expected 200."
  exit 1
fi

echo "PASS: no invalid weights remain and payments-service returns 200."
exit 0
