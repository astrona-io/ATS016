#!/usr/bin/env bash
# PASS when /tmp/ats-016-bug-report/bug-report.tar.gz exists and is a readable
# gzip-compressed tar archive.
set -uo pipefail

ARCHIVE="/tmp/ats-016-bug-report/bug-report.tar.gz"

if [ ! -f "$ARCHIVE" ]; then
  echo "FAIL: $ARCHIVE does not exist."
  echo "      Write the archive there with: istioctl bug-report ... --output-dir /tmp/ats-016-bug-report"
  exit 1
fi
if ! tar tzf "$ARCHIVE" >/dev/null 2>&1; then
  echo "FAIL: $ARCHIVE is not a readable .tar.gz archive."
  exit 1
fi
echo "PASS: $ARCHIVE exists and can be read."
exit 0
