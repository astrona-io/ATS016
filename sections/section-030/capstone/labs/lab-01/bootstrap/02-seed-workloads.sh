#!/usr/bin/env bash
# Creates the starting state for ats-016-capstone-030.
#
# Three independent control plane faults:
#   1. orders-service carries a pod-template injection opt-out.
#   2. cpcapstone-legacy is pinned to a revision that does not exist.
#   3. An invalid VirtualService (redirect and route in one rule) is stored
#      while istiod is down and both validating webhooks are relaxed.
#
# istiod is left RUNNING: the learner must find three faults, not one outage.
set -euo pipefail

MAIN="cpcapstone-demo"
LEGACY="cpcapstone-legacy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"
# Istio installs two validating webhooks (the revision one and the default
# one); both must be relaxed, or the API server still refuses the object.
WEBHOOKS="$(kubectl get validatingwebhookconfiguration -o name | grep -E 'istio' | sed 's#.*/##')"

echo "[capstone] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl apply -f "$MANIFESTS/legacy-namespace.yaml"
for d in orders-service payments-service tester; do
  kubectl -n "$MAIN" rollout status "deployment/$d" --timeout=300s
done
kubectl -n "$LEGACY" rollout status deployment/billing-service --timeout=300s

echo "[capstone] Storing an invalid VirtualService while no webhook can check it..."
kubectl -n istio-system scale deploy istiod --replicas=0
kubectl -n istio-system rollout status deploy istiod --timeout=120s
# A running istiod switches the webhooks back to Fail, so relax them only
# after its pods are gone.
for _ in $(seq 1 60); do
  kubectl -n istio-system get pods -l app=istiod -o name 2>/dev/null | grep -q . || break
  sleep 2
done
echo "[capstone] Relaxing both validating webhooks so the invalid object can be stored..."
for W in $WEBHOOKS; do
  kubectl patch validatingwebhookconfiguration "$W" --type json \
    -p '[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]' >/dev/null
done
kubectl apply -f "$MANIFESTS/invalid-route.yaml" || {
  echo "[capstone] ERROR: the invalid object could not be stored; a webhook is still enforcing." >&2
  exit 1
}
kubectl -n istio-system scale deploy istiod --replicas=1
kubectl -n istio-system rollout status deploy istiod --timeout=300s
for W in $WEBHOOKS; do
  kubectl patch validatingwebhookconfiguration "$W" --type json \
    -p '[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Fail"}]' >/dev/null 2>&1 || true
done

echo "[capstone] Starting state ready. The control plane is healthy."
kubectl -n "$MAIN" get pods -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
kubectl -n "$LEGACY" get pods -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
