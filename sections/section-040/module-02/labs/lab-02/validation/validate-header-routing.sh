#!/usr/bin/env bash
# PASS when ten requests with "testing: true" all reach v2 and ten requests
# without it all reach v1.
set -uo pipefail
NS="portproto-demo"
WITH="$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST -H "testing: true" http://notification-service/notify; echo; done' 2>/dev/null | sort -u)"
WITHOUT="$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' 2>/dev/null | sort -u)"
rc=0
if [ "$WITH" != '["EMAIL","SMS"]' ]; then
  echo "FAIL: requests with the testing header did not all reach v2. Answers seen:"
  printf '  %s\n' $WITH
  rc=1
fi
if [ "$WITHOUT" != '["EMAIL"]' ]; then
  echo "FAIL: requests without the header did not all reach v1. Answers seen:"
  printf '  %s\n' $WITHOUT
  rc=1
fi
[ $rc -eq 0 ] && echo "PASS: the header route sends testing=true to v2 and everything else to v1."
exit $rc
