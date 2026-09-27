#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-050-01.
#
# Applies the workloads plus a VirtualService that injects a 5s delay on every
# request, standing in for a slow dependency. No Telemetry object and no
# timeout are created — both are the task.
set -euo pipefail

NAMESPACE="accesslog-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[lab] Applying the slow-dependency simulation..."
kubectl apply -f "$MANIFESTS/slow-dependency.yaml"

echo "[lab] Starting state ready. Requests currently hang for about five seconds."
kubectl -n "$NAMESPACE" get virtualservice
