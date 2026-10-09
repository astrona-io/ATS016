# Overview: Debug A 503 Caused By A Missing Subset (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH. The `demo` profile enables Envoy access logging, which this module
  relies on.
- The injected namespace **`fivezerothree-demo`**, containing:
  - `notification-service-v1` — labelled `version: v1`, behind the Service
    `notification-service` on port 80.
  - `tester` — a client pod with `curl`.
- **A live 503** (`manifests/broken-config.yaml`): a `DestinationRule` defining
  only subset `v1`, and a `VirtualService` routing to subset `v2`. Every request
  fails on arrival. Follow the chain before reading the manifest.

## Things to try

- Get the response flag from the access log before running anything else, and
  write down what you predict the chain will show.
- Fix it the *wrong* way — add a `v2` subset to the `DestinationRule` with
  labels no pod carries — and watch the flag change from `NC` to `UH`. That
  transition is the clearest demonstration in this module.
- Scale `notification-service-v1` to zero with correct routing in place, and see
  a third variant of the same status code.
- Rename the Service port from `http` to `web`, restart, and find out how many
  things break at once.
- Compare the access logs of `tester` and `notification-service-v1` during a
  failure, and confirm the destination never sees the request.
