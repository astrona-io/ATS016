#!/usr/bin/env bash
# PASS when both subset clusters resolve to at least one HEALTHY endpoint.
set -uo pipefail

NS="proxycfg-demo"
FQDN="notification-service.$NS.svc.cluster.local"
rc=0

for SUB in v1 v2; do
  CLUSTER="outbound|80|$SUB|$FQDN"
  OUT="$(istioctl proxy-config endpoint deploy/tester -n "$NS" --cluster "$CLUSTER" 2>/dev/null)"
  N="$(printf '%s\n' "$OUT" | grep -c 'HEALTHY' || true)"
  if [ "$N" -lt 1 ]; then
    echo "FAIL: cluster '$CLUSTER' has no HEALTHY endpoint."
    echo "      A subset whose labels match no pod is not a valid answer."
    rc=1
  else
    echo "ok: $SUB has $N healthy endpoint(s)."
  fi
done

[ $rc -eq 0 ] && echo "PASS: both subset clusters resolve to healthy endpoints."
exit $rc
