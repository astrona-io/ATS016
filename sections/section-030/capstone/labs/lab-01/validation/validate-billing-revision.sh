#!/usr/bin/env bash
# PASS when cpcapstone-legacy names an injection target that exists AND
# billing-service carries a sidecar.
set -uo pipefail

NS="cpcapstone-legacy"

REV="$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.istio\.io/rev}' 2>/dev/null)"
INJ="$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)"

if [ -z "$REV" ] && [ -z "$INJ" ]; then
  echo "FAIL: $NS carries no injection label at all."
  exit 1
fi

if [ -n "$REV" ]; then
  INSTALLED="$(kubectl -n istio-system get pods -l app=istiod \
    -o jsonpath='{range .items[*]}{.metadata.labels.istio\.io/rev}{"\n"}{end}' 2>/dev/null | sort -u)"
  if ! printf '%s\n' "$INSTALLED" | grep -qx "$REV"; then
    echo "FAIL: $NS is pinned to revision '$REV', which is not installed."
    echo "      Installed revisions: $(printf '%s ' $INSTALLED)"
    exit 1
  fi
fi

C="$(kubectl -n "$NS" get pods -l app=billing-service \
  -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null)"
if ! printf '%s' "$C" | grep -q 'istio-proxy'; then
  echo "FAIL: billing-service containers are '$C' — no istio-proxy."
  echo "      A label change does not recreate pods; restart the Deployment."
  exit 1
fi

echo "PASS: $NS targets an existing control plane and billing-service is injected."
exit 0
