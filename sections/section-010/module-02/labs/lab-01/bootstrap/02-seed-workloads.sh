#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-010-02.
#
# Applies the workloads and four Istio objects that all select one workload:
# a STRICT PeerAuthentication, a DestinationRule, a VirtualService, and an
# AuthorizationPolicy that allows only POST.
#
# It also leaves the notification proxy's `rbac` log scope at `debug`, as an
# on-call engineer would have done during an earlier investigation.
set -euo pipefail

NAMESPACE="describe-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[lab] Applying the mesh policies..."
kubectl apply -f "$MANIFESTS/policies.yaml"
sleep 5

POD="$(kubectl -n "$NAMESPACE" get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')"
echo "[lab] Leaving the rbac log scope at debug on $POD (as a previous investigation would have)..."
istioctl proxy-config log "$POD" -n "$NAMESPACE" --level rbac:debug >/dev/null

echo "[lab] Starting state ready."
kubectl -n "$NAMESPACE" get pods
echo "[lab] GET requests are currently refused by the AuthorizationPolicy."
