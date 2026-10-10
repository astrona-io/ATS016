#!/usr/bin/env bash
# Runs before the reference solution is applied.
#
# `astrona test` bootstraps and applies in one go, and istiod's validating
# webhook is registered before it is reachable: applying an Istio object in that
# window fails outright with
#   Internal error occurred: failed calling webhook "validation.istio.io":
#   dial tcp ...:443: connect: connection refused
# which looks like a broken manifest and is not one.
set -eu

for _ in $(seq 1 90); do
  if kubectl -n istio-system get endpoints istiod \
       -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | grep -q .; then
    # The endpoint exists; confirm the webhook actually answers.
    if kubectl get --raw '/readyz' >/dev/null 2>&1 && \
       kubectl -n istio-system get deployment istiod \
         -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -qE '^[1-9]'; then
      sleep 3
      exit 0
    fi
  fi
  sleep 2
done
