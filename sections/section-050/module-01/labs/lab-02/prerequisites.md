# Prerequisites

Before starting this lab you should be able to:

- Read an Envoy access log line in the default format and find the status, the response flag and the response code details.
- Tell from the upstream cluster field (`outbound|…` or `inbound|…`) which proxy wrote a line.
- Read an `AuthorizationPolicy` and a `DestinationRule` `connectionPool` and say what each controls.

## What the environment gives you

The lab environment builds itself before the task begins:

- A single-node `kind` Kubernetes cluster, with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. Access logging is on for the whole mesh.
- The namespace **`accesslog-demo`**, prepared as the task describes.

## Working rules

- Everything is graded on the **final cluster state**, so re-run the failing
  requests at the end and leave the fix in place.
- Change one thing at a time and re-test. A second speculative change makes the
  first one unverifiable.
- `kubectl`, `istioctl` and `curl` are available. No internet access is needed
  once the environment is up.
