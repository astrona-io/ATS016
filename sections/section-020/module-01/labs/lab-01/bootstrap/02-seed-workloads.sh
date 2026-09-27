#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-020-01.
#
# Two versions of notification-service, plus two VirtualService objects that
# both claim the same host, one of which shadows its own header rule behind a
# catch-all. Neither object is invalid; both applied without complaint.
set -euo pipefail

NAMESPACE="conflict-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
for d in notification-service-v1 notification-service-v2 tester; do
  kubectl -n "$NAMESPACE" rollout status "deployment/$d" --timeout=300s
done

echo "[lab] Applying the conflicting routing configuration..."
kubectl apply -f "$MANIFESTS/broken-config.yaml"

echo "[lab] Starting state ready."
kubectl -n "$NAMESPACE" get virtualservice
echo "[lab] The testing=true header currently has no effect. Finding out why is the task."
