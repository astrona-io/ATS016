# Overview: Find Configuration Errors With istioctl analyze (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH.
- The injected namespace **`analyze-demo`**, containing:
  - `notification-service-v1` — a Deployment labelled `version: v1`, behind the
    Service `notification-service` on port 80.
  - `tester` — a client pod with `curl`.
- **Deliberately broken Istio configuration** (`manifests/broken-config.yaml`):
  a `VirtualService` that routes to a subset no `DestinationRule` defines and
  binds to a `Gateway` that does not exist. Both objects applied without a
  single complaint from the API server, which is the point.

## Things to try

- Run `istioctl analyze -n analyze-demo` before reading
  `manifests/broken-config.yaml`. Then read the file and check whether the
  analyzer found everything you would have.
- Remove the injection label from the namespace
  (`kubectl label namespace analyze-demo istio-injection-`) and re-run analyze.
  A new `Warning` appears where nothing is technically invalid.
- Delete the `DestinationRule` entirely and predict the message code before you
  re-run the analyzer.
- Compare `istioctl validate -f` against `istioctl analyze --use-kube=false` on
  the same file, and again on a file containing only the `VirtualService`.
- Try `istioctl analyze --failure-threshold Warning -n analyze-demo` and watch
  the exit code change — that is the form a CI pipeline uses.
