# Overview: Debug A Workload With No Sidecar (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH.
- The namespace **`noinject-demo`**, labelled `istio-injection=enabled`,
  containing:
  - `notification-service-v1` — a normally injected workload, for comparison.
  - `reporting-service` — an HTTP service that is **not** in the mesh. The
    reason is in its pod template; find it with the checklist rather than by
    reading `manifests/lab-start.yaml` first.
  - `tester` — a client pod with `curl`.

## Things to try

- Work the checklist in order on `reporting-service` before you look at the
  manifest, and note which step eliminated which possibility.
- Fix it, then break it a different way: remove the namespace label, restart,
  and confirm both workloads leave the mesh.
- Add the label back but do **not** restart. Watch nothing happen, which is the
  point of step three.
- Set the sidecar injector webhook's `failurePolicy` to `Ignore`, scale `istiod`
  to zero, and create a pod — then look at how silent the result is.
- Label the namespace `istio.io/rev=nonexistent` alongside
  `istio-injection=enabled` and work out, from `istioctl proxy-status`, which
  one actually won.
