#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-050-02.
#
# A STRICT PeerAuthentication on the server, and a DestinationRule telling the
# client to send plaintext. Both objects are valid; together they guarantee a
# handshake failure on every request.
set -euo pipefail

NAMESPACE="mtlsfail-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[lab] Applying the conflicting mTLS configuration..."
kubectl apply -f "$MANIFESTS/broken-config.yaml"
sleep 5

echo "[lab] Starting state ready. Every request currently fails."
kubectl -n "$NAMESPACE" get peerauthentication,destinationrule
