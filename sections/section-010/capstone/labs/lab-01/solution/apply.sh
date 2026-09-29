#!/usr/bin/env bash
# Reference remediation, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so the lab stays broken for the student.
# Taken from solution.md - if one changes, change the other.
#
# These labs start from a broken cluster, so the fix is frequently a delete or a
# restart. A manifest applied with `kubectl apply` cannot express either, which
# is why this is a script.
set -eu

kubectl label namespace audit-demo istio-injection=enabled
kubectl -n audit-demo rollout restart deployment notification-service-v1 tester
kubectl -n audit-demo rollout status deployment/notification-service-v1 --timeout=180s
kubectl -n audit-demo rollout status deployment/tester --timeout=180s

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: audit-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
            subset: v1
EOF

kubectl -n audit-demo patch authorizationpolicy notification-post-only --type json \
  -p '[{"op":"replace","path":"/spec/selector/matchLabels/app","value":"notification-service"}]'

# Let the change reach the proxies before the checks read them back.
sleep 12
