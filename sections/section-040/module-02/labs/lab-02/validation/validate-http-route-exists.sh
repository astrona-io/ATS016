#!/usr/bin/env bash
# PASS when the tester proxy holds an HTTP virtual host for notification-service
# whose first route matches the testing header, proving the port is handled as
# HTTP and the VirtualService applies.
set -uo pipefail
NS="portproto-demo"
JSON="$(istioctl proxy-config route deploy/tester -n "$NS" -o json 2>/dev/null)"
if [ -z "$JSON" ]; then
  echo "FAIL: could not read the route configuration from the tester proxy."
  exit 1
fi
RESULT="$(printf '%s' "$JSON" | python3 -c '
import json,sys
data=json.load(sys.stdin)
routes=None
def walk(o):
    global routes
    if isinstance(o,dict):
        for vh in o.get("virtualHosts",[]) or []:
            if routes is None and any(d.startswith("notification-service") for d in vh.get("domains",[])):
                routes=vh.get("routes",[])
        for v in o.values(): walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
walk(data)
if routes is None:
    print("NOVHOST"); raise SystemExit
first=routes[0] if routes else {}
hdrs=[h.get("name") for h in first.get("match",{}).get("headers",[])]
print("OK" if "testing" in hdrs else "NOHEADER")')"
case "$RESULT" in
  OK) echo "PASS: the tester proxy has an HTTP route for notification-service with the testing header rule first." ; exit 0 ;;
  NOVHOST) echo "FAIL: the tester proxy holds no HTTP virtual host for notification-service."
           echo "      A port declared as TCP gets no route stage, so no VirtualService rule can apply." ; exit 1 ;;
  *) echo "FAIL: the HTTP route for notification-service does not start with the testing header rule."
     echo "      Do not change the VirtualService; fix how the Service port is declared." ; exit 1 ;;
esac
