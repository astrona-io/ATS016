#!/usr/bin/env bash
# PASS when no HTTP rule has both a redirect and a route, and payments-service answers.
set -uo pipefail

NS="cpcapstone-demo"

BAD="$(kubectl -n "$NS" get virtualservice -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
bad=[]
for item in d.get("items",[]):
    name=item["metadata"]["name"]
    for idx,rule in enumerate(item.get("spec",{}).get("http",[]) or []):
        if rule.get("redirect") and rule.get("route"):
            bad.append(f"{name} http[{idx}] has both redirect and route")
print("\n".join(bad))')"

if [ -n "$BAD" ]; then
  echo "FAIL: invalid route rule(s) still present:"
  printf '  %s\n' "$BAD"
  exit 1
fi

CODE="$(kubectl -n "$NS" exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}' http://payments-service/get 2>/dev/null)"
if [ "$CODE" != "200" ]; then
  echo "FAIL: a request to payments-service returned '$CODE', expected 200."
  exit 1
fi

echo "PASS: no invalid route rule remains and payments-service returns 200."
exit 0
