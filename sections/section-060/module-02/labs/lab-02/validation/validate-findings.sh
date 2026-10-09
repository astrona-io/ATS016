#!/usr/bin/env bash
# PASS when the ConfigMap `findings` in callers-demo records what PromQL shows:
#   failing-caller = reports-client  (the only source_workload with 5xx)
#   reporter       = source          (the abort happens in the client proxy)
#   response-flag  = FI              (fault injected)
set -uo pipefail
NS="callers-demo"
if ! kubectl -n "$NS" get configmap findings >/dev/null 2>&1; then
  echo "FAIL: no ConfigMap named 'findings' in $NS."
  exit 1
fi
read_key() {
  kubectl -n "$NS" get configmap findings -o "jsonpath={.data.$1}" 2>/dev/null \
    | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'
}
rc=0
check_key() {
  local key="$1" want="$2" got
  got="$(read_key "$key")"
  if [ "$got" != "$want" ]; then
    echo "FAIL: findings.$key is '${got:-<missing>}'; it does not match what the metrics show."
    rc=1
  else
    echo "ok: findings.$key is correct."
  fi
}
check_key "failing-caller" "reports-client"
check_key "reporter" "source"
check_key "response-flag" "fi"
[ $rc -eq 0 ] && echo "PASS: the findings match the metrics."
exit $rc
