# Prerequisites

Before starting this lab you should be able to:

- Use `kubectl` to inspect and edit objects in a namespace.
- Read a `VirtualService` and a `DestinationRule` and say what each controls.
- Send a test request from one pod to another with `curl`.

## What the environment gives you

The lab environment builds itself before the task begins:

- A single-node `kind` Kubernetes cluster, with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH.
- The namespace(s) **`routing-demo`**, prepared as the task describes.

Nothing the task asks you to create has been created for you.

## Working rules

- Everything is graded on the **final cluster state**, so re-run the failing
  request at the end and leave the fix in place.
- Change one thing at a time and re-test. A second speculative change makes the
  first one unverifiable.
- `kubectl`, `istioctl` and `curl` are available. No internet access is needed
  once the environment is up.
