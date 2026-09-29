#!/usr/bin/env bash
# Reference remediation, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so the lab stays broken for the student.
# Taken from solution.md - if one changes, change the other.
#
# These labs start from a broken cluster, so the fix is frequently a delete or a
# restart. A manifest applied with `kubectl apply` cannot express either, which
# is why this is a script.
set -eu

kubectl -n cpcapstone-demo patch deployment orders-service --type json \
  -p '[{"op":"remove","path":"/spec/template/metadata/labels/sidecar.istio.io~1inject"}]'
kubectl -n cpcapstone-demo rollout status deployment/orders-service --timeout=180s

istioctl tag list

kubectl label namespace cpcapstone-legacy istio.io/rev-
kubectl label namespace cpcapstone-legacy istio-injection=enabled
kubectl -n cpcapstone-legacy rollout restart deployment billing-service
kubectl -n cpcapstone-legacy rollout status deployment/billing-service --timeout=180s

kubectl -n cpcapstone-demo delete virtualservice payments-split --ignore-not-found

# Let the change reach the proxies before the checks read them back.
sleep 12
