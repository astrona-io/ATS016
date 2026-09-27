#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-060-01.
#
# Workloads plus a VirtualService that references a Gateway and a subset that do
# not exist. No traffic is generated, so the Kiali graph starts empty — which is
# the first thing the learner has to recognise as normal rather than broken.
set -euo pipefail

NAMESPACE="kiali-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[lab] Applying the broken Istio configuration..."
kubectl apply -f "$MANIFESTS/broken-config.yaml"

echo "[lab] Starting state ready."
kubectl -n istio-system get pods -l app=kiali
echo "[lab] No traffic is flowing yet, so the Kiali graph is empty. That is expected."
