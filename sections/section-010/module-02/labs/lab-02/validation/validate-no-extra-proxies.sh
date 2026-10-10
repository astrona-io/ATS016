#!/usr/bin/env bash
# PASS when every proxy in the archive belongs to the notification-service-v1
# Deployment in describe-demo: no tester pod, no noise-demo pod and no gateway.
#
# This is the check that rejects an unscoped capture.
set -uo pipefail

ARCHIVE="/tmp/ats-016-bug-report/bug-report.tar.gz"

# Strip the leading bug-report/ folder, which is absent when --dir is used.
LIST="$(tar tzf "$ARCHIVE" 2>/dev/null | sed -e 's#^\./##' -e 's#^bug-report/##')"
if [ -z "$LIST" ]; then
  echo "FAIL: cannot list $ARCHIVE."
  exit 1
fi

PODS="$(printf '%s\n' "$LIST" | grep '^proxies/' | cut -d/ -f2-3 | grep -E '^[^/]+/[^/]+$' | sort -u)"
if [ -z "$PODS" ]; then
  echo "FAIL: the archive holds no proxy data at all."
  echo "      The archive holds these folders (first 30):"
  tar tzf "$ARCHIVE" 2>/dev/null | cut -d/ -f1-4 | sort -u | head -30 | sed 's/^/        /'
  exit 1
fi

EXTRA="$(printf '%s\n' "$PODS" | grep -v '^describe-demo/notification-service-v1-' || true)"
if [ -n "$EXTRA" ]; then
  echo "FAIL: the archive holds proxies that were not asked for:"
  printf '      %s\n' $EXTRA
  echo "      Limit the capture with one --include selector to the notification-service-v1 Deployment and istiod."
  exit 1
fi
echo "PASS: the only proxy in the archive is notification-service-v1 in describe-demo."
exit 0
