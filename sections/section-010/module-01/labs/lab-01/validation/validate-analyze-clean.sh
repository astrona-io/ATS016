#!/usr/bin/env bash
# PASS when istioctl analyze reports no validation issues in analyze-demo.
set -uo pipefail

NS="analyze-demo"
OUT="$(istioctl analyze -n "$NS" 2>&1)"
RC=$?

if [ $RC -ne 0 ] || printf '%s' "$OUT" | grep -qE '^(Error|Warning) \[IST'; then
  echo "FAIL: istioctl analyze still reports findings in $NS:"
  printf '%s\n' "$OUT"
  exit 1
fi

echo "PASS: istioctl analyze reports no validation issues in $NS."
exit 0
