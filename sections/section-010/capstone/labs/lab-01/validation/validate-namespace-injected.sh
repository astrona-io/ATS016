#!/usr/bin/env bash
# PASS when the namespace is labelled for injection and every pod has a sidecar.
set -uo pipefail

NS="audit-demo"

LABEL="$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)"
REV="$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.istio\.io/rev}' 2>/dev/null)"
if [ -z "$LABEL" ] && [ -z "$REV" ]; then
  echo "FAIL: $NS carries no injection label."
  exit 1
fi

rc=0
while read -r POD CONTAINERS; do
  [ -z "$POD" ] && continue
  if ! printf '%s' "$CONTAINERS" | grep -q 'istio-proxy'; then
    echo "FAIL: pod $POD has containers '$CONTAINERS' — no istio-proxy."
    echo "      Labelling the namespace does not affect pods that already exist."
    rc=1
  fi
done <<< "$(kubectl -n "$NS" get pods --field-selector=status.phase=Running \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .spec.initContainers[*]}{.name}{","}{end}{range .spec.containers[*]}{.name}{","}{end}{"\n"}{end}')"

[ $rc -eq 0 ] && echo "PASS: namespace is labelled and every running pod carries a sidecar."
exit $rc
