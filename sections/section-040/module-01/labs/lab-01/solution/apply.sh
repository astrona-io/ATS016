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

# Wait for the pods being replaced to actually go away. `rollout status` returns
# as soon as the new pod is available, while the old one is still terminating -
# and a terminating pod still reports phase Running, so both the checks and
# `istioctl analyze` see a workload "missing the Istio proxy" that is on its way
# out. Then give the proxies a moment to receive the new configuration.
for _ in $(seq 1 60); do
  leaving=$(kubectl get pods -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null \
    | grep -vE '^(kube-system|kube-public|kube-node-lease|local-path-storage) ' \
    | awk 'NF>1')
  [ -z "$leaving" ] && break
  sleep 2
done
sleep 8
