# Overview: Summarise A Workload With describe, Capture A Cluster With bug-report (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH.
- The injected namespace **`describe-demo`**, containing:
  - `notification-service-v1` — a Deployment labelled `version: v1`, behind the
    Service `notification-service` on port 80.
  - `tester` — a client pod with `curl`.
- **Four Istio objects that all land on that one workload**
  (`manifests/policies.yaml`): a namespace-wide `PeerAuthentication` in
  `STRICT` mode, a `DestinationRule` with subset `v1`, a `VirtualService`
  routing to it, and an `AuthorizationPolicy` allowing only `POST`.

Nothing is broken here. The environment exists so you can practise reading a
working system rather than repairing a failing one.

## Things to try

- Write down what you expect `istioctl x describe pod` to say about mTLS and
  routing, then run it and check yourself.
- Remove the `name: http` from the Service port, re-run `describe`, and find the
  protocol warning. Watch what stops working in the same breath.
- Change the `AuthorizationPolicy` selector to a label no pod carries, re-run
  `describe`, and see how an inert policy is reported.
- Follow one request end to end with `--level connection:debug` instead of
  `rbac:debug`, then put the level back.
- Run `istioctl bug-report` twice, once with `--include describe-demo` and once
  without, and compare how long each takes and how large the archive is.
