#!/usr/bin/env bash
# Creates the starting state for ats-016-capstone-050.
#
# Two stacked failures. The mTLS mismatch fails first, so the authorization
# fault is invisible until it is fixed — the learner has to work them in order.
set -euo pipefail

NAMESPACE="logcapstone-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[capstone] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[capstone] Applying the security configuration..."
kubectl apply -f "$MANIFESTS/broken-config.yaml"
sleep 5

echo "[capstone] Starting state ready. Every request fails; there are two reasons."
kubectl -n "$NAMESPACE" get peerauthentication,destinationrule,authorizationpolicy
