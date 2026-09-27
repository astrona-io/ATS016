#!/usr/bin/env bash
# Creates the starting state for ats-016-capstone-020.
#
# Two versions of notification-service, and THREE VirtualService objects that
# all claim the same host on the mesh gateway. One of them also shadows its own
# header rule behind a catch-all.
set -euo pipefail

NAMESPACE="routing-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[capstone] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
for d in notification-service-v1 notification-service-v2 tester; do
  kubectl -n "$NAMESPACE" rollout status "deployment/$d" --timeout=300s
done

echo "[capstone] Applying the routing configuration..."
kubectl apply -f "$MANIFESTS/broken-config.yaml"

echo "[capstone] Starting state ready."
kubectl -n "$NAMESPACE" get virtualservice \
  -o custom-columns='NAME:.metadata.name,HOSTS:.spec.hosts,GATEWAYS:.spec.gateways'
echo "[capstone] Neither the header rule nor the URI rule reliably fires."
