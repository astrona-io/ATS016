#!/usr/bin/env bash
# PASS when a DestinationRule defines v1 and v2 over the version label.
set -uo pipefail

NS="proxycfg-demo"

OUT="$(kubectl -n "$NS" get destinationrule -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
found={}
for item in d.get("items",[]):
    spec=item.get("spec",{})
    if spec.get("host","").split(".")[0] != "notification-service":
        continue
    for s in spec.get("subsets",[]) or []:
        found[s.get("name")] = s.get("labels") or {}
for want in ("v1","v2"):
    if want not in found:
        print(f"MISSING {want}")
    elif found[want].get("version") != want:
        print(f"WRONGLABELS {want} {found[want]}")
')"

if [ -n "$OUT" ]; then
  echo "FAIL: subsets are not defined as required:"
  printf '  %s\n' "$OUT"
  echo "      Expected subsets v1 and v2 selecting version=v1 and version=v2."
  exit 1
fi

echo "PASS: subsets v1 and v2 are defined over the version label."
exit 0
