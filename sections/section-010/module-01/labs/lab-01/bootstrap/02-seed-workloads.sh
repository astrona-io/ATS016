#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-010-01.
#
# Applies the workloads, then applies configuration that is schema-valid and
# semantically broken: a VirtualService routing to a subset no DestinationRule
# defines, bound to a Gateway that does not exist.
#
# The corrected configuration is NOT applied here — producing it is the task.
set -euo pipefail

NAMESPACE="analyze-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"

kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[lab] Applying the broken Istio configuration..."
kubectl apply -f "$MANIFESTS/broken-config.yaml"

echo "[lab] Starting state ready."
kubectl -n "$NAMESPACE" get pods
echo "[lab] Requests to notification-service currently fail. Diagnosing that is the task."
