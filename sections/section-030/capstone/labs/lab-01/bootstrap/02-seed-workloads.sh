#!/usr/bin/env bash
# Creates the starting state for ats-016-capstone-030.
#
# Three independent control plane faults:
#   1. orders-service carries a pod-template injection opt-out.
#   2. cpcapstone-legacy is pinned to a revision that does not exist.
#   3. An invalid weighted VirtualService is stored while istiod is down and
#      the validating webhook is relaxed, so it exists and will never be pushed.
#
# istiod is left RUNNING: the learner must find three faults, not one outage.
set -euo pipefail

MAIN="cpcapstone-demo"
LEGACY="cpcapstone-legacy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"
WEBHOOK="istio-validator-istio-system"

echo "[capstone] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl apply -f "$MANIFESTS/legacy-namespace.yaml"
for d in orders-service payments-service tester; do
  kubectl -n "$MAIN" rollout status "deployment/$d" --timeout=300s
done
kubectl -n "$LEGACY" rollout status deployment/billing-service --timeout=300s

echo "[capstone] Storing a configuration istiod will never accept..."
kubectl patch validatingwebhookconfiguration "$WEBHOOK" --type json \
  -p '[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]' >/dev/null 2>&1 || true
kubectl -n istio-system scale deploy istiod --replicas=0
kubectl -n istio-system rollout status deploy istiod --timeout=120s
kubectl apply -f "$MANIFESTS/bad-weights.yaml" || \
  echo "[capstone] WARNING: the invalid object could not be stored."
kubectl -n istio-system scale deploy istiod --replicas=1
kubectl -n istio-system rollout status deploy istiod --timeout=300s
kubectl patch validatingwebhookconfiguration "$WEBHOOK" --type json \
  -p '[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Fail"}]' >/dev/null 2>&1 || true

echo "[capstone] Starting state ready. The control plane is healthy."
kubectl -n "$MAIN" get pods -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
kubectl -n "$LEGACY" get pods -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
