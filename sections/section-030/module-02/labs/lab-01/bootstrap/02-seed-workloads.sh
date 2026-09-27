#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-030-02.
#
# Brings the namespace up fully meshed, then removes the injection label and
# restarts one workload so its replacement pod comes up with no sidecar. The
# pod is healthy by every Kubernetes measure and absent from proxy-status.
set -euo pipefail

NAMESPACE="proxysync-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[lab] Removing the injection label and recycling one workload..."
kubectl label namespace "$NAMESPACE" istio-injection- --overwrite >/dev/null
kubectl -n "$NAMESPACE" rollout restart deployment notification-service-v1
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s

echo "[lab] Starting state ready."
kubectl -n "$NAMESPACE" get pods
echo "[lab] One workload is running without a sidecar and does not appear in proxy-status."
