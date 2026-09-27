#!/usr/bin/env bash
# PASS when the PeerAuthentication is still STRICT and the DestinationRule survives.
set -uo pipefail

NS="mtlsfail-demo"

MODE="$(kubectl -n "$NS" get peerauthentication -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
modes=[i.get("spec",{}).get("mtls",{}).get("mode","UNSET") for i in d.get("items",[])]
print(modes[0] if modes else "NONE")')"

if [ "$MODE" != "STRICT" ]; then
  echo "FAIL: PeerAuthentication mode is '$MODE', expected STRICT."
  echo "      Relaxing the server accepts plaintext from every caller — fix the client instead."
  exit 1
fi

if ! kubectl -n "$NS" get destinationrule notification >/dev/null 2>&1; then
  echo "FAIL: the DestinationRule was deleted. Remove only the tls override."
  exit 1
fi

TLS="$(kubectl -n "$NS" get destinationrule notification \
  -o jsonpath='{.spec.trafficPolicy.tls.mode}' 2>/dev/null)"
if [ "$TLS" = "DISABLE" ]; then
  echo "FAIL: the client DestinationRule still sets tls.mode: DISABLE."
  exit 1
fi

echo "PASS: server is STRICT, DestinationRule kept, client no longer disables TLS."
exit 0
