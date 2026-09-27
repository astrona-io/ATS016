#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-040-02.
#
# One version of notification-service, a DestinationRule defining only v1, and
# a VirtualService routing to a subset called v2 that nothing defines. Every
# request fails before it leaves the client pod.
set -euo pipefail

NAMESPACE="fivezerothree-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[lab] Applying the broken routing..."
kubectl apply -f "$MANIFESTS/broken-config.yaml"

echo "[lab] Starting state ready. Requests currently return 503."
kubectl -n "$NAMESPACE" get pods
