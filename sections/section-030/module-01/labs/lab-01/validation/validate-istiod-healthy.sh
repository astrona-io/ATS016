#!/usr/bin/env bash
# PASS when istiod is scaled up, Running and ready.
set -uo pipefail

READY="$(kubectl -n istio-system get deploy istiod -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
DESIRED="$(kubectl -n istio-system get deploy istiod -o jsonpath='{.spec.replicas}' 2>/dev/null)"

if [ -z "$DESIRED" ] || [ "$DESIRED" -lt 1 ] 2>/dev/null; then
  echo "FAIL: istiod is scaled to ${DESIRED:-0}. The control plane must be restored."
  exit 1
fi
if [ -z "$READY" ] || [ "$READY" -lt 1 ] 2>/dev/null; then
  echo "FAIL: istiod has no ready replica (ready=${READY:-0}, desired=$DESIRED)."
  exit 1
fi

if ! istioctl proxy-status >/dev/null 2>&1; then
  echo "FAIL: istioctl proxy-status cannot reach the control plane."
  exit 1
fi

echo "PASS: istiod is Running with $READY/$DESIRED ready and serving config."
exit 0
