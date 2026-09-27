#!/usr/bin/env bash
# PASS when the tester proxy's route table sends an exact testing=true match to
# the v2 cluster, with the v1 catch-all after it.
set -uo pipefail

NS="proxycfg-demo"
FQDN="notification-service.$NS.svc.cluster.local"

JSON="$(istioctl proxy-config route deploy/tester -n "$NS" --name 80 -o json 2>/dev/null)"
if [ -z "$JSON" ]; then
  echo "FAIL: could not read the route configuration from the tester proxy."
  exit 1
fi

RESULT="$(printf '%s' "$JSON" | python3 -c "
import json,sys
data=json.load(sys.stdin)
routes=[]
def walk(o):
    if isinstance(o,dict):
        if 'virtualHosts' in o:
            for vh in o['virtualHosts']:
                if any('notification-service' in d for d in vh.get('domains',[])):
                    for r in vh.get('routes',[]):
                        routes.append(r)
        for v in o.values(): walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
walk(data)
if not routes:
    print('NOROUTES'); raise SystemExit
first=routes[0]
hdrs=first.get('match',{}).get('headers',[])
ok_hdr=any(h.get('name')=='testing' and
           (h.get('stringMatch',{}).get('exact')=='true' or h.get('exactMatch')=='true')
           for h in hdrs)
c1=first.get('route',{}).get('cluster','')
last=routes[-1]
c2=last.get('route',{}).get('cluster','')
print('HDR' if ok_hdr else 'NOHDR', c1, c2, len(routes))
")"

set -- $RESULT
STATE="${1:-}"; C1="${2:-}"; C2="${3:-}"; N="${4:-0}"

if [ "$STATE" = "NOROUTES" ]; then
  echo "FAIL: the proxy holds no routes for notification-service."
  exit 1
fi
if [ "$STATE" != "HDR" ]; then
  echo "FAIL: the first route does not match exactly on the 'testing' header."
  echo "      Found first-route cluster: $C1"
  exit 1
fi
if ! printf '%s' "$C1" | grep -q "|v2|$FQDN"; then
  echo "FAIL: the header route selects '$C1', expected the v2 subset cluster."
  exit 1
fi
if ! printf '%s' "$C2" | grep -q "|v1|$FQDN"; then
  echo "FAIL: the last route selects '$C2', expected the v1 catch-all."
  exit 1
fi

echo "PASS: header match -> v2, catch-all -> v1, in that order ($N routes)."
exit 0
