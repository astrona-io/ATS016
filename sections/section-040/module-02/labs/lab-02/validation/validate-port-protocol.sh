#!/usr/bin/env bash
# PASS when the notification-service port declares an HTTP protocol (by name or
# appProtocol) and still maps 80 -> 8084.
set -uo pipefail
NS="portproto-demo"
read -r NAME APPPROTO PORT TARGET <<<"$(kubectl -n "$NS" get svc notification-service -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
p=d["spec"]["ports"][0]
print(p.get("name","") or "-", p.get("appProtocol","") or "-", p.get("port"), p.get("targetPort"))')"
if [ -z "${NAME:-}" ]; then
  echo "FAIL: could not read the notification-service Service in $NS."
  exit 1
fi
OK=0
# appProtocol takes precedence over the port name, so check it first.
case "$APPPROTO" in
  http|http2|grpc) OK=1 ;;
  -) case "$NAME" in http|http-*|http2|http2-*|grpc|grpc-*) OK=1 ;; esac ;;
esac
if [ "$OK" -ne 1 ]; then
  echo "FAIL: the port is named '$NAME' with appProtocol '$APPPROTO'."
  echo "      Istio reads the protocol from appProtocol, then from the port name; neither declares HTTP."
  exit 1
fi
if [ "$PORT" != "80" ] || [ "$TARGET" != "8084" ]; then
  echo "FAIL: the port mapping changed to $PORT->$TARGET; it must stay 80->8084."
  exit 1
fi
echo "PASS: the port declares HTTP (name='$NAME', appProtocol='$APPPROTO') and still maps 80->8084."
exit 0
