#!/usr/bin/env bash
# Reference remediation, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so the lab stays broken for the student.
# Taken from solution.md - if one changes, change the other.
#
# These labs start from a broken cluster, so the fix is frequently a delete or a
# restart. A manifest applied with `kubectl apply` cannot express either, which
# is why this is a script.
set -eu

kubectl apply -f - <<'EOF'
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-logs
  namespace: accesslog-demo
spec:
  accessLogging:
    - providers:
        - name: envoy
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: accesslog-demo
spec:
  hosts:
    - notification-service
  http:
    - fault:
        delay:
          fixedDelay: 5s
          percentage:
            value: 100
      timeout: 2s
      route:
        - destination:
            host: notification-service
EOF

# Let the change reach the proxies before the checks read them back.
sleep 12
