#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-060-02.
#
# Workloads plus a VirtualService injecting a 30% abort and a 500ms delay on
# half of all requests, standing in for a partially failing dependency. The
# learner measures it before removing it.
set -euo pipefail

NAMESPACE="metrics-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[lab] Injecting the partial failure..."
kubectl apply -f "$MANIFESTS/fault.yaml"

echo "[lab] Starting state ready. About 30% of requests currently fail."
kubectl -n "$NAMESPACE" get virtualservice
