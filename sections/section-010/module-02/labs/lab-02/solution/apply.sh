#!/usr/bin/env bash
# Reference remediation, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so the learner starts with no archive.
# Taken from solution.md - if one changes, change the other.
set -eu
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

ARCHIVE_DIR="/tmp/ats-016-bug-report"
mkdir -p "$ARCHIVE_DIR"

istioctl bug-report \
  --include describe-demo/notification-service-v1 \
  --include istio-system/istiod \
  --duration 10m \
  --output-dir "$ARCHIVE_DIR"
