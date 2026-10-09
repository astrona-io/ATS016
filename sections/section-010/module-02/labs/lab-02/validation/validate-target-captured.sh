#!/usr/bin/env bash
# PASS when the archive holds the configuration dump of the CURRENT
# notification-service pod in describe-demo, and istiod data from istio-system.
#
# Proxy data sits under bug-report/proxies/<namespace>/<pod>/ and istiod data
# under bug-report/istio/<namespace>/<pod>/ (istioctl 1.30 archive layout).
# Matching the current pod name rejects an archive taken from another cluster.
set -uo pipefail

ARCHIVE="/tmp/ats-016-bug-report/bug-report.tar.gz"
NS="describe-demo"

# Strip the leading bug-report/ folder, which is absent when --dir is used.
LIST="$(tar tzf "$ARCHIVE" 2>/dev/null | sed -e 's#^\./##' -e 's#^bug-report/##')"
if [ -z "$LIST" ]; then
  echo "FAIL: cannot list $ARCHIVE."
  exit 1
fi

POD="$(kubectl -n "$NS" get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -z "$POD" ]; then
  echo "FAIL: no notification-service pod found in $NS."
  exit 1
fi

rc=0
if printf '%s\n' "$LIST" | grep -q "^proxies/$NS/$POD/config_dump"; then
  echo "ok: the archive holds the configuration dump of $NS/$POD."
else
  echo "FAIL: no configuration dump for $NS/$POD under bug-report/proxies/."
  echo "      Include the notification-service-v1 Deployment in the capture."
  rc=1
fi
if printf '%s\n' "$LIST" | grep -q '^istio/istio-system/istiod-'; then
  echo "ok: the archive holds istiod data."
else
  echo "FAIL: no istiod data under bug-report/istio/istio-system/."
  echo "      istiod is only collected when an --include matches it."
  rc=1
fi
[ $rc -eq 0 ] && echo "PASS: the target proxy and istiod were captured."
exit $rc
