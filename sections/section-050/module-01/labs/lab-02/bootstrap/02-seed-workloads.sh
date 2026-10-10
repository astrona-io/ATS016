#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-050-01-02.
#
# Applies the workloads, then a DENY policy that lists the wrong method and a
# connection pool far too small for a burst of requests. Both objects are
# valid; the task is to find each one from the access logs and correct it.
set -euo pipefail

NAMESPACE="accesslog-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[lab] Applying the faulty policy and connection pool..."
kubectl apply -f "$MANIFESTS/broken-config.yaml"
sleep 5

echo "[lab] Starting state ready. POST returns 403, and bursts also return 503."
kubectl -n "$NAMESPACE" get authorizationpolicy,destinationrule
