#!/usr/bin/env bash
# PASS when the notification workload's pods carry the istio-proxy container.
set -uo pipefail

NS="proxysync-demo"

CONTAINERS="$(kubectl -n "$NS" get pods -l app=notification-service \
  -o jsonpath='{.items[0].spec.initContainers[*].name} {.items[0].spec.containers[*].name}' 2>/dev/null)"

if [ -z "$CONTAINERS" ]; then
  echo "FAIL: no notification-service pod found in $NS."
  exit 1
fi

if ! printf '%s' "$CONTAINERS" | grep -q 'istio-proxy'; then
  echo "FAIL: the pod's containers are '$CONTAINERS' — no istio-proxy."
  echo "      Label the namespace for injection AND recreate the pods."
  exit 1
fi

LABEL="$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)"
REV="$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.istio\.io/rev}' 2>/dev/null)"
if [ -z "$LABEL" ] && [ -z "$REV" ]; then
  echo "FAIL: the namespace carries no injection label, so the fix will not survive a pod replacement."
  exit 1
fi

echo "PASS: notification-service carries istio-proxy and the namespace is labelled for injection."
exit 0
