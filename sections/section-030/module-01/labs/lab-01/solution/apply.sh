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

# istiod was scaled to zero in this lab, so the pre-flight wait could not help:
# the webhook only becomes reachable once the fix above brings it back. Applying
# an Istio object before then fails with "failed calling webhook
# validation.istio.io: connect: connection refused".
for _ in $(seq 1 90); do
  kubectl -n istio-system get endpoints istiod \
    -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | grep -q . && break
  sleep 2
done
sleep 5

kubectl -n cphealth-demo delete virtualservice bad-redirect --ignore-not-found

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bad-redirect
  namespace: cphealth-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
EOF

# Bringing istiod back is only half of it: each proxy has to re-establish its
# xDS connection before it shows up in `istioctl proxy-status`, and that takes
# noticeably longer than the Deployment becoming ready. Wait for the namespace's
# proxies to come back rather than guessing at a sleep.
for _ in $(seq 1 60); do
  # grep -c exits 1 when it matches nothing, which would fail the assignment
  # under set -e before the proxies have had a chance to reconnect.
  seen=$(istioctl proxy-status 2>/dev/null | grep -c 'cphealth-demo' || true)
  [ "${seen:-0}" -ge 2 ] && break
  sleep 3
done

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
