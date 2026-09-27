#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-030-03.
#
# The namespace is labelled for injection and most workloads are meshed. One
# Deployment carries an opt-out on its POD TEMPLATE, so its pods come up with
# no sidecar while looking healthy in every Kubernetes view.
set -euo pipefail

NAMESPACE="noinject-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
for d in notification-service-v1 reporting-service tester; do
  kubectl -n "$NAMESPACE" rollout status "deployment/$d" --timeout=300s
done

echo "[lab] Starting state ready."
kubectl -n "$NAMESPACE" get pods \
  -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
echo "[lab] One workload has one container where the others have two."
