#!/usr/bin/env bash
# PASS when the notification proxy's rbac log scope is back at info.
set -uo pipefail

NS="describe-demo"
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

POD="$(kubectl -n "$NS" get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -z "$POD" ]; then
  echo "FAIL: no notification-service pod found in $NS."
  exit 1
fi

LEVELS="$(istioctl proxy-config log "$POD" -n "$NS" 2>/dev/null)"
if [ -z "$LEVELS" ]; then
  echo "FAIL: could not read log levels from $POD."
  exit 1
fi

RBAC="$(printf '%s\n' "$LEVELS" | grep -E '^rbac:' | awk '{print $2}')"
if [ "$RBAC" != "info" ]; then
  echo "FAIL: the rbac log scope is '$RBAC', expected 'info'."
  echo "      Restore it with: istioctl proxy-config log $POD -n $NS --level rbac:info"
  exit 1
fi

echo "PASS: the rbac log scope is back at info."
exit 0
