#!/usr/bin/env bash
# Reference remediation, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so the lab stays broken for the student.
# Taken from solution.md - if one changes, change the other.
set -eu

kubectl -n portproto-demo patch svc notification-service --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/name","value":"http"}]'

# istiod pushes the new listeners and routes over xDS; give the tester proxy a
# moment to receive them before the checks run.
for _ in $(seq 1 30); do
  if istioctl proxy-config route deploy/tester -n portproto-demo -o json 2>/dev/null \
       | grep -q 'notification-service.portproto-demo'; then
    break
  fi
  sleep 2
done
sleep 5
