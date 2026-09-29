#!/usr/bin/env bash
# Reference remediation, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so the lab stays broken for the student.
# Taken from solution.md - if one changes, change the other.
#
# These labs start from a broken cluster, so the fix is frequently a delete or a
# restart. A manifest applied with `kubectl apply` cannot express either, which
# is why this is a script.
set -eu

kubectl -n metrics-demo delete virtualservice notification --ignore-not-found
sleep 70

kubectl apply -f - <<'EOF'
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-logs
  namespace: metrics-demo
spec:
  accessLogging:
    - providers:
        - name: envoy
EOF

# Let the change reach the proxies before the checks read them back.
sleep 12
