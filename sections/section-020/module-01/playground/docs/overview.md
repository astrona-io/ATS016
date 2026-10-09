# Overview: Debug Conflicting And Shadowed Routes (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: a training solar system in the simulator. The environment starts clean, runs `bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, `astrona destroy`, and start over.

## What is in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your PATH.
- The planet (namespace) **`conflict-demo`**, with sidecar injection on, holding:
  - `notification-service-v1` and `notification-service-v2` behind one Service, `notification-service`, on port 80. `v1` answers `["EMAIL"]` and `v2` answers `["EMAIL","SMS"]`, so the reply tells you which one answered.
  - `tester`: a client pod with `curl`, your test ship.
- **Routing in conflict on purpose** (`manifests/broken-config.yaml`): a `DestinationRule` with subsets `v1` and `v2`, a `VirtualService` whose catch-all route sits above its header rule, and a second `VirtualService` claiming the same host.

## Things to try

- Fix only the rule order, leaving both `VirtualService` objects in place, and send the header request many times. Decide for yourself whether you would ship the result.
- Delete `notification-extra` first instead, and watch which symptom moves.
- Compare `istioctl proxy-config routes deploy/tester -n conflict-demo -o json` before and after each change. The route table is the only record of what really happened.
- Give the second `VirtualService` a different host and run `istioctl analyze` again. The `IST0109` warning should disappear.
- Add a third rule matching `uri: prefix: /notify` below the catch-all, then confirm from the route table that it never appears.
