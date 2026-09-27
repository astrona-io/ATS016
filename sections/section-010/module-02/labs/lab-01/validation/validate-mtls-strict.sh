#!/usr/bin/env bash
# PASS when the effective mTLS mode for the workload is still STRICT.
set -uo pipefail

NS="describe-demo"
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

MODE="$(kubectl -n "$NS" get peerauthentication -o json \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)
modes=[i.get("spec",{}).get("mtls",{}).get("mode","UNSET") for i in d.get("items",[])]
print(modes[0] if modes else "NONE")')"

if [ "$MODE" != "STRICT" ]; then
  echo "FAIL: PeerAuthentication mode is '$MODE', expected STRICT."
  echo "      Relaxing mTLS is not a fix for an authorization problem."
  exit 1
fi

POD="$(kubectl -n "$NS" get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -n "$POD" ] && command -v istioctl >/dev/null 2>&1; then
  if ! istioctl x describe pod "$POD" -n "$NS" 2>/dev/null | grep -qi 'STRICT'; then
    echo "FAIL: istioctl x describe pod does not report an effective STRICT mode."
    exit 1
  fi
fi

echo "PASS: effective mTLS mode is still STRICT."
exit 0
