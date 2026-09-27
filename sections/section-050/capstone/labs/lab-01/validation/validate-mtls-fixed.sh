#!/usr/bin/env bash
# PASS when the server is still STRICT and the client no longer disables TLS.
set -uo pipefail

NS="logcapstone-demo"

MODE="$(kubectl -n "$NS" get peerauthentication default -o jsonpath='{.spec.mtls.mode}' 2>/dev/null)"
if [ "$MODE" != "STRICT" ]; then
  echo "FAIL: PeerAuthentication mode is '$MODE', expected STRICT."
  echo "      Relaxing the server is not a fix for a client misconfiguration."
  exit 1
fi

if ! kubectl -n "$NS" get destinationrule notification >/dev/null 2>&1; then
  echo "FAIL: the DestinationRule was deleted. Remove only the tls override."
  exit 1
fi

TLS="$(kubectl -n "$NS" get destinationrule notification \
  -o jsonpath='{.spec.trafficPolicy.tls.mode}' 2>/dev/null)"
if [ "$TLS" = "DISABLE" ]; then
  echo "FAIL: the client DestinationRule still sets tls.mode: DISABLE."
  exit 1
fi

POOL="$(kubectl -n "$NS" get destinationrule notification \
  -o jsonpath='{.spec.trafficPolicy.connectionPool.tcp.maxConnections}' 2>/dev/null)"
if [ -z "$POOL" ]; then
  echo "FAIL: the connectionPool setting was removed along with the tls block."
  echo "      Only the tls override should have been deleted."
  exit 1
fi

echo "PASS: server STRICT, client TLS override removed, connection pool preserved."
exit 0
