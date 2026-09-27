#!/usr/bin/env bash
# Creates the starting state for ats-016-capstone-040.
#
# Two failures that both look like "the service is broken", at two different
# stages of Envoy's request handling:
#   1. notification-service - a route to a subset nothing defines (cluster stage)
#   2. reporting-service    - a Service port named "web", so no protocol is
#                             declared and no HTTP route is ever built
set -euo pipefail

NAMESPACE="dpcapstone-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[capstone] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
for d in notification-service-v1 reporting-service tester; do
  kubectl -n "$NAMESPACE" rollout status "deployment/$d" --timeout=300s
done

echo "[capstone] Applying the routing configuration..."
kubectl apply -f "$MANIFESTS/broken-config.yaml"

echo "[capstone] Starting state ready."
kubectl -n "$NAMESPACE" get svc
echo "[capstone] Both services misbehave, for two different reasons."
