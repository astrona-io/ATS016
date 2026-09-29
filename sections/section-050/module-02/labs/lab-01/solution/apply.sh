#!/usr/bin/env bash
# Reference remediation, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so the lab stays broken for the student.
# Taken from solution.md - if one changes, change the other.
#
# These labs start from a broken cluster, so the fix is frequently a delete or a
# restart. A manifest applied with `kubectl apply` cannot express either, which
# is why this is a script.
set -eu

kubectl -n mtlsfail-demo patch destinationrule notification --type json \
  -p '[{"op":"remove","path":"/spec/trafficPolicy"}]'

# Let the change reach the proxies before the checks read them back.
sleep 12
