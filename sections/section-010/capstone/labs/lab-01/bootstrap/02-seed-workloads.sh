#!/usr/bin/env bash
# Creates the starting state for ats-016-capstone-010.
#
# An unlabelled namespace, a VirtualService with two dangling references, and an
# AuthorizationPolicy whose selector matches nothing. Every object applied
# cleanly; nothing works as intended.
set -euo pipefail

NAMESPACE="audit-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[capstone] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[capstone] Applying the namespace's Istio configuration..."
kubectl apply -f "$MANIFESTS/broken-config.yaml"

echo "[capstone] Starting state ready."
kubectl -n "$NAMESPACE" get pods \
  -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
echo "[capstone] Every object exists. None of them does what its author intended."
