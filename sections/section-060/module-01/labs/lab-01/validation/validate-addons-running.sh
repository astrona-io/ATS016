#!/usr/bin/env bash
# PASS when the Prometheus and Kiali addons are Running.
set -uo pipefail
rc=0

check() {
  local label="$1" name="$2"
  local phase
  phase="$(kubectl -n istio-system get pods -l "$label" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
  if [ "$phase" != "Running" ]; then
    echo "FAIL: $name is not Running (phase='${phase:-absent}')."
    rc=1
  else
    echo "ok: $name is Running."
  fi
}

check "app=kiali" "Kiali"
check "app.kubernetes.io/name=prometheus" "Prometheus"

[ $rc -eq 0 ] && echo "PASS: both Kiali data sources are Running."
exit $rc
