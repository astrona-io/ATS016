#!/usr/bin/env bash
# PASS when the tester proxy holds an HTTP route for reporting-service, proving
# the port is treated as HTTP rather than passed through as TCP.
set -uo pipefail

NS="dpcapstone-demo"

ROUTES="$(istioctl proxy-config route deploy/tester -n "$NS" -o json 2>/dev/null | python3 -c '
import json,sys
data=json.load(sys.stdin)
hosts=[]
def walk(o):
    if isinstance(o,dict):
        if "virtualHosts" in o:
            for vh in o["virtualHosts"]:
                hosts.extend(vh.get("domains",[]))
        for v in o.values(): walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
walk(data)
print("\n".join(sorted(set(hosts))))')"

if ! printf '%s\n' "$ROUTES" | grep -q 'reporting-service'; then
  echo "FAIL: the proxy holds no HTTP virtual host for reporting-service."
  echo "      A port with no declared protocol gets no route stage at all."
  exit 1
fi

LISTENER="$(istioctl proxy-config listener deploy/tester -n "$NS" --port 80 2>/dev/null)"
if ! printf '%s\n' "$LISTENER" | grep -q 'Route:'; then
  echo "FAIL: no port-80 listener hands off to a Route; traffic is still passed through."
  printf '%s\n' "$LISTENER"
  exit 1
fi

echo "PASS: an HTTP route exists for reporting-service and the listener hands off to it."
exit 0
