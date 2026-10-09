#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-040-02-02.
#
# Two versions of notification-service behind one Service whose port is
# declared as TCP (`tcp-notify`), plus correct header routing. The routing is
# never applied, because the client proxy builds no HTTP route for a TCP port.
# Finding that out from the proxy and fixing the declaration is the task.
set -euo pipefail

NAMESPACE="portproto-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
for d in notification-service-v1 notification-service-v2 tester; do
  kubectl -n "$NAMESPACE" rollout status "deployment/$d" --timeout=300s
done

# istiod's validating webhook can be registered before it answers; retry the
# Istio objects until it does.
echo "[lab] Applying the routing..."
for _ in $(seq 1 30); do
  kubectl apply -f "$MANIFESTS/routing.yaml" && break
  sleep 4
done
kubectl -n "$NAMESPACE" get virtualservice notification >/dev/null

echo "[lab] Starting state ready: the Service port is declared as TCP."
kubectl -n "$NAMESPACE" get pods
kubectl -n "$NAMESPACE" get svc notification-service -o jsonpath='{.spec.ports}{"\n"}'
