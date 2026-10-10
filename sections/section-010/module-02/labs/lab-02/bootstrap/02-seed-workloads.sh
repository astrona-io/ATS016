#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-010-02-02.
#
# Applies the describe-demo workloads and their four Istio objects (the same
# starting state as the module's playground), plus a second injected namespace,
# noise-demo, whose proxies the learner must leave out of the archive.
#
# It removes any archive left over from an earlier run, so the grader only ever
# sees an archive the learner produced against this cluster.
set -euo pipefail

NAMESPACE="describe-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"
ARCHIVE_DIR="/tmp/ats-016-bug-report"
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

rm -rf "$ARCHIVE_DIR"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl apply -f "$MANIFESTS/noise.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s
kubectl -n noise-demo rollout status deployment/tester --timeout=300s

echo "[lab] Applying the mesh policies..."
kubectl apply -f "$MANIFESTS/policies.yaml"

echo "[lab] Starting state ready."
kubectl -n "$NAMESPACE" get pods
kubectl -n noise-demo get pods
echo "[lab] GET requests to notification-service are refused by the AuthorizationPolicy."
