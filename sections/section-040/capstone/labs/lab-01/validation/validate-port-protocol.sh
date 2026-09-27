#!/usr/bin/env bash
# PASS when the reporting-service port declares an HTTP protocol.
set -uo pipefail

NS="dpcapstone-demo"

read -r NAME APPPROTO PORT TARGET <<<"$(kubectl -n "$NS" get svc reporting-service -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
p=d["spec"]["ports"][0]
print(p.get("name","") or "-", p.get("appProtocol","") or "-", p.get("port"), p.get("targetPort"))')"

OK=0
case "$NAME" in http|http-*|http2|http2-*|grpc|grpc-*) OK=1 ;; esac
case "$APPPROTO" in http|http2|grpc) OK=1 ;; esac

if [ "$OK" -ne 1 ]; then
  echo "FAIL: the reporting-service port is named '$NAME' with appProtocol '$APPPROTO'."
  echo "      Istio infers the protocol from the port name or appProtocol; neither declares HTTP."
  exit 1
fi

if [ "$PORT" != "80" ] || [ "$TARGET" != "8080" ]; then
  echo "FAIL: the port mapping changed to $PORT->$TARGET; it must stay 80->8080."
  exit 1
fi

echo "PASS: the port declares HTTP (name='$NAME', appProtocol='$APPPROTO') and still maps 80->8080."
exit 0
