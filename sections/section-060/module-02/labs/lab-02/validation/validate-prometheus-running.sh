#!/usr/bin/env bash
# PASS when the Prometheus addon is Running, so the learner's queries had a
# source to answer them.
set -uo pipefail
phase="$(kubectl -n istio-system get pods -l app.kubernetes.io/name=prometheus \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
if [ "$phase" != "Running" ]; then
  echo "FAIL: Prometheus is not Running (phase='${phase:-absent}')."
  exit 1
fi
echo "PASS: Prometheus is Running."
exit 0
