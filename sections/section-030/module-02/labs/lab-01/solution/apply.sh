#!/usr/bin/env bash
# Reference remediation, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so the lab stays broken for the student.
# Taken from solution.md - if one changes, change the other.
#
# These labs start from a broken cluster, so the fix is frequently a delete or a
# restart. A manifest applied with `kubectl apply` cannot express either, which
# is why this is a script.
set -eu

kubectl label namespace proxysync-demo istio-injection=enabled
kubectl -n proxysync-demo rollout restart deployment notification-service-v1
kubectl -n proxysync-demo rollout status deployment/notification-service-v1 --timeout=180s

# Let the change reach the proxies before the checks read them back.
sleep 12
