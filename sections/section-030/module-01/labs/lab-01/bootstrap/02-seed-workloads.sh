#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-030-01.
#
# Reproduces the "accepted and never applied" failure honestly:
#   1. temporarily sets the validating webhook failurePolicy to Ignore,
#   2. scales istiod to zero,
#   3. applies a VirtualService whose route weights sum to 120 — which the
#      webhook would normally reject, and which now lands in etcd unvalidated,
#   4. restores the webhook's failurePolicy,
#   5. LEAVES istiod scaled to zero.
#
# The learner therefore arrives at a mesh where traffic still flows, nothing
# can change, and one stored object will never be pushed.
set -euo pipefail

NAMESPACE="cphealth-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"
WEBHOOK="istio-validator-istio-system"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[lab] Relaxing the validating webhook so the invalid object can be stored..."
kubectl patch validatingwebhookconfiguration "$WEBHOOK" --type json \
  -p '[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]' >/dev/null 2>&1 || true

echo "[lab] Scaling istiod to zero..."
kubectl -n istio-system scale deploy istiod --replicas=0
kubectl -n istio-system rollout status deploy istiod --timeout=120s

echo "[lab] Applying configuration that istiod will never accept..."
kubectl apply -f "$MANIFESTS/bad-weights.yaml" || \
  echo "[lab] WARNING: the invalid object could not be stored; the webhook may still be enforcing."

echo "[lab] Restoring the validating webhook failurePolicy..."
kubectl patch validatingwebhookconfiguration "$WEBHOOK" --type json \
  -p '[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Fail"}]' >/dev/null 2>&1 || true

echo "[lab] Starting state ready. istiod is DOWN and one stored object is invalid."
kubectl -n istio-system get deploy istiod
kubectl -n "$NAMESPACE" get pods
