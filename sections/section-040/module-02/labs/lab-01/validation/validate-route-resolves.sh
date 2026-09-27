#!/usr/bin/env bash
# PASS when every cluster the route table names for notification-service also
# exists in the proxy's cluster list.
set -uo pipefail

NS="fivezerothree-demo"

ROUTED="$(istioctl proxy-config routes deploy/tester -n "$NS" -o json 2>/dev/null \
  | grep '"cluster"' | grep notification | sed 's/.*"cluster": "//; s/".*//' | sort -u)"

if [ -z "$ROUTED" ]; then
  echo "FAIL: the proxy route table names no cluster for notification-service."
  exit 1
fi

CLUSTERS="$(istioctl proxy-config cluster deploy/tester -n "$NS" -o json 2>/dev/null \
  | grep '"name"' | sed 's/.*"name": "//; s/".*//')"

rc=0
for C in $ROUTED; do
  if printf '%s\n' "$CLUSTERS" | grep -qxF "$C"; then
    echo "ok: route target exists -> $C"
  else
    echo "FAIL: the route names '$C', which does not exist in the proxy's cluster list."
    rc=1
  fi
done

[ $rc -eq 0 ] && echo "PASS: every routed cluster exists in the proxy configuration."
exit $rc
