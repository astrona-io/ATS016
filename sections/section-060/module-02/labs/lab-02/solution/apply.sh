#!/usr/bin/env bash
# Reference remediation, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so the lab stays broken for the student.
# Same objects as solution/solution.yaml and solution.md - if one changes,
# change the others.
set -eu

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: findings
  namespace: callers-demo
data:
  failing-caller: reports-client
  reporter: source
  response-flag: FI
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: callers-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
YAML

# Give the sidecar proxies a moment to receive the route without the fault.
sleep 10
