#!/usr/bin/env bash
# Creates the starting state for ats-016-lab-060-02-02.
#
# Two clients (orders-client and reports-client) call notification-service in a
# loop from the moment they start. A VirtualService aborts 25% of the requests
# from reports-client only, in reports-client's own sidecar proxy. The learner
# finds the affected caller with PromQL before removing the fault.
set -euo pipefail

NAMESPACE="callers-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$SCRIPT_DIR/../manifests"

echo "[lab] Applying starting workloads..."
kubectl apply -f "$MANIFESTS/lab-start.yaml"
for d in notification-service-v1 tester orders-client reports-client; do
  kubectl -n "$NAMESPACE" rollout status "deployment/$d" --timeout=300s
done

echo "[lab] Injecting the fault for one caller..."
kubectl apply -f "$MANIFESTS/fault.yaml"

echo "[lab] Starting state ready. One of the two clients is getting errors."
kubectl -n "$NAMESPACE" get pods
