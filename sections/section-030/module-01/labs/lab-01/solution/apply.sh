#!/usr/bin/env bash
# Reference remediation, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so the lab stays broken for the student.
# Taken from solution.md - if one changes, change the other.
#
# These labs start from a broken cluster, so the fix is frequently a delete or a
# restart. A manifest applied with `kubectl apply` cannot express either, which
# is why this is a script.
set -eu

kubectl -n istio-system scale deploy istiod --replicas=1
kubectl -n istio-system rollout status deploy istiod --timeout=180s

kubectl -n cphealth-demo delete virtualservice bad-weights --ignore-not-found

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bad-weights
  namespace: cphealth-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
          weight: 100
EOF

# Let the change reach the proxies before the checks read them back.
sleep 12
