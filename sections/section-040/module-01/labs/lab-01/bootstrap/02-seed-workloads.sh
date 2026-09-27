#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-040-01.
#
# Two versions of notification-service behind one Service, plus a client — and
# deliberately NO Istio traffic configuration. Writing it, and then proving it
# from the proxy's own configuration, is the task.
set -euo pipefail

NAMESPACE="proxycfg-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
for d in notification-service-v1 notification-service-v2 tester; do
  kubectl -n "$NAMESPACE" rollout status "deployment/$d" --timeout=300s
done

echo "[lab] Starting state ready — no VirtualService or DestinationRule exists."
kubectl -n "$NAMESPACE" get pods
kubectl -n "$NAMESPACE" get virtualservice,destinationrule 2>&1 | tail -1
