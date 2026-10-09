#!/usr/bin/env bash
# Reference remediation, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so the lab stays broken for the student.
# Taken from solution.md - if one changes, change the other.
set -eu

# Fault 1: the DENY policy must block DELETE, not POST.
kubectl -n accesslog-demo patch authorizationpolicy block-delete --type json \
  -p '[{"op":"replace","path":"/spec/rules/0/to/0/operation/methods","value":["DELETE"]}]'

# Fault 2: keep the connection pool, but large enough for a burst of 20.
kubectl -n accesslog-demo patch destinationrule notification --type merge \
  -p '{"spec":{"trafficPolicy":{"connectionPool":{"tcp":{"maxConnections":100},"http":{"http1MaxPendingRequests":100}}}}}'

# Give the proxies a moment to receive the new configuration.
sleep 8
