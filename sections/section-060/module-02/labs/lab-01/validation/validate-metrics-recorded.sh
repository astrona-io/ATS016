#!/usr/bin/env bash
# PASS when Prometheus holds istio_requests_total for the workload with a 200
# response code, and a Telemetry object declares access logging.
set -uo pipefail

NS="metrics-demo"
rc=0

TEL="$(kubectl -n "$NS" get telemetry -o json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("NONE"); raise SystemExit
for item in d.get("items",[]):
    for al in item.get("spec",{}).get("accessLogging",[]) or []:
        if al.get("disabled"): continue
        for p in al.get("providers",[]) or []:
            if p.get("name")=="envoy": print("OK"); raise SystemExit
print("NONE")')"
if [ "$TEL" != "OK" ]; then
  echo "FAIL: no Telemetry object in $NS enables the 'envoy' access log provider."
  rc=1
else
  echo "ok: access logging is declared for $NS."
fi

kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 5); do curl -s -o /dev/null -X POST http://notification-service/notify; done' >/dev/null 2>&1 || true
sleep 20

RESP="$(kubectl -n "$NS" exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' \
  --data-urlencode 'query=sum(istio_requests_total{destination_workload="notification-service-v1",response_code="200"})' 2>/dev/null)"

VALUE="$(printf '%s' "$RESP" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("ERR"); raise SystemExit
r=d.get("data",{}).get("result",[])
print(r[0]["value"][1] if r else "0")')"

if [ "$VALUE" = "ERR" ]; then
  echo "FAIL: could not query Prometheus at prometheus.istio-system:9090."
  rc=1
elif [ "${VALUE%%.*}" -lt 1 ] 2>/dev/null; then
  echo "FAIL: Prometheus holds no istio_requests_total series with response_code=200 (value=$VALUE)."
  rc=1
else
  echo "ok: Prometheus reports $VALUE successful requests for the workload."
fi

[ $rc -eq 0 ] && echo "PASS: metrics are being recorded and access logging is declared."
exit $rc
