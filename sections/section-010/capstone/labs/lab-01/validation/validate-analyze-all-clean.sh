#!/usr/bin/env bash
# PASS when analyze reports no Error and no Warning for the namespace.
set -uo pipefail

NS="audit-demo"
OUT="$(istioctl analyze -n "$NS" 2>&1)"

if printf '%s' "$OUT" | grep -qE '^(Error|Warning) \[IST'; then
  echo "FAIL: analyze still reports Error/Warning findings in $NS:"
  printf '%s\n' "$OUT" | grep -E '^(Error|Warning) \[IST'
  exit 1
fi

echo "PASS: no Error or Warning findings in $NS."
exit 0
