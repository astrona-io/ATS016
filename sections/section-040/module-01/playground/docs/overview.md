# Overview: Read The Proxy Configuration (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH.
- The injected namespace **`proxycfg-demo`**, containing:
  - `notification-service-v1` — labelled `version: v1`, behind the Service
    `notification-service` on port 80, targeting container port 8084.
  - `tester` — a client pod with `curl`.
- **Working routing** (`manifests/routing.yaml`): a `DestinationRule` with
  subset `v1` and a `VirtualService` with a header match plus a default route.

Nothing is broken. This environment exists so you can learn what a correct
proxy configuration looks like at each of the four stages — which is the only
way to recognise a wrong one later.

## Things to try

- Walk `listener → route → cluster → endpoint` for one request, writing down the
  exact name each stage hands to the next.
- Point the `VirtualService` at a subset named `v3` and follow the same chain.
  Find the exact stage where it breaks.
- Scale `notification-service-v1` to zero and watch the endpoint list empty out
  while the cluster stays exactly where it was.
- Compare `istioctl proxy-config cluster deploy/tester` (outbound) with the same
  command against `deploy/notification-service-v1` (inbound).
- Remove `name: http` from the Service port, restart, and see what happens to
  the port-80 listener and its route.
- Run `istioctl proxy-config all deploy/tester -o json | wc -l` once, to see what
  you are being spared by the narrowing flags.
