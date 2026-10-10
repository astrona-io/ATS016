#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-030-01.
#
# Reproduces the "stored without validation" failure honestly:
#   1. scales istiod to zero (a running istiod resets the webhooks to Fail),
#   2. temporarily sets both validating webhooks' failurePolicy to Ignore,
#   3. applies a VirtualService with redirect and route in one rule - which the
#      webhook would normally reject, and which now lands in etcd unvalidated,
#   4. restores the webhook's failurePolicy,
#   5. LEAVES istiod scaled to zero.
#
# The learner therefore arrives at a mesh where traffic still flows, nothing
# can change, and one invalid object is stored. Once istiod is back, it
# serves that object as it is, and requests get a 301 redirect.
set -euo pipefail

NAMESPACE="cphealth-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"
# Istio installs two validating webhooks (the revision one and the default
# one); both must be relaxed, or the API server still refuses the object.
WEBHOOKS="$(kubectl get validatingwebhookconfiguration -o name | grep -E 'istio' | sed 's#.*/##')"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/tester --timeout=300s

echo "[lab] Scaling istiod to zero..."
kubectl -n istio-system scale deploy istiod --replicas=0
kubectl -n istio-system rollout status deploy istiod --timeout=120s
# A running istiod switches the webhooks back to Fail, so relax them only
# after its pods are gone.
for _ in $(seq 1 60); do
  kubectl -n istio-system get pods -l app=istiod -o name 2>/dev/null | grep -q . || break
  sleep 2
done

echo "[lab] Relaxing both validating webhooks so the invalid object can be stored..."
for W in $WEBHOOKS; do
  kubectl patch validatingwebhookconfiguration "$W" --type json \
    -p '[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]' >/dev/null
done

echo "[lab] Storing an invalid VirtualService while no webhook can check it..."
kubectl apply -f "$MANIFESTS/invalid-route.yaml" || {
  echo "[lab] ERROR: the invalid object could not be stored; a webhook is still enforcing." >&2
  exit 1
}

echo "[lab] Restoring the validating webhook failurePolicy..."
for W in $WEBHOOKS; do
  kubectl patch validatingwebhookconfiguration "$W" --type json \
    -p '[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Fail"}]' >/dev/null 2>&1 || true
done

echo "[lab] Starting state ready. istiod is DOWN and one stored object is invalid."
kubectl -n istio-system get deploy istiod
kubectl -n "$NAMESPACE" get pods
