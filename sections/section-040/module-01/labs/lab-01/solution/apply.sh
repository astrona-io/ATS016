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
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification
  namespace: proxycfg-demo
spec:
  host: notification-service
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: proxycfg-demo
spec:
  hosts:
    - notification-service
  http:
    - match:
        - headers:
            testing:
              exact: "true"
      route:
        - destination:
            host: notification-service
            subset: v2
    - route:
        - destination:
            host: notification-service
            subset: v1
EOF

# Let the change reach the proxies before the checks read them back.
sleep 12
