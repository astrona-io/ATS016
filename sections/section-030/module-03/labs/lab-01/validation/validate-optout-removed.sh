#!/usr/bin/env bash
# PASS when the pod template no longer carries a sidecar.istio.io/inject opt-out
# and the namespace label was left alone.
set -uo pipefail

NS="noinject-demo"

VAL="$(kubectl -n "$NS" get deploy reporting-service \
  -o jsonpath='{.spec.template.metadata.labels.sidecar\.istio\.io/inject}' 2>/dev/null)"
if [ "$VAL" = "false" ]; then
  echo "FAIL: the pod template still carries sidecar.istio.io/inject=false."
  exit 1
fi

NSLABEL="$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)"
if [ "$NSLABEL" != "enabled" ]; then
  echo "FAIL: the namespace injection label is '$NSLABEL', expected 'enabled' (it must not be changed)."
  exit 1
fi

echo "PASS: the pod-template opt-out is gone and the namespace label is untouched."
exit 0
