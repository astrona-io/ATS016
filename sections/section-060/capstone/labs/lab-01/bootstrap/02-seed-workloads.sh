#!/usr/bin/env bash
# Creates the starting state for ats-016-capstone-060.
#
# Prometheus, Kiali and Grafana are installed by the previous bootstrap step.
# This adds the workloads, a 40% abort fault, and a second VirtualService that
# claims the same host and routes to a subset nothing defines.
#
# No traffic is generated: the graph and the dashboards start empty, which is
# the first thing the learner has to recognise as normal.
set -euo pipefail

NAMESPACE="obscapstone-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[capstone] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[capstone] Applying the routing configuration..."
kubectl apply -f "$MANIFESTS/broken-config.yaml"

echo "[capstone] Starting state ready."
kubectl -n istio-system get pods -l app=kiali
kubectl -n "$NAMESPACE" get virtualservice
echo "[capstone] No traffic is flowing yet, so every dashboard is empty."
