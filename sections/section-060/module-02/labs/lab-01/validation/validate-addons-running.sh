#!/usr/bin/env bash
# PASS when the Prometheus and Grafana addons are Running.
set -uo pipefail
rc=0

check() {
  local label="$1" name="$2" phase
  phase="$(kubectl -n istio-system get pods -l "$label" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
  if [ "$phase" != "Running" ]; then
    echo "FAIL: $name is not Running (phase='${phase:-absent}')."
    rc=1
  else
    echo "ok: $name is Running."
  fi
}

check "app.kubernetes.io/name=prometheus" "Prometheus"
check "app.kubernetes.io/name=grafana" "Grafana"

[ $rc -eq 0 ] && echo "PASS: Prometheus and Grafana are Running."
exit $rc
