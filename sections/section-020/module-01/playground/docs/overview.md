# Overview: Debug Conflicting And Shadowed Routes (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH.
- The injected namespace **`conflict-demo`**, containing:
  - `notification-service-v1` and `notification-service-v2` behind one Service,
    `notification-service`, on port 80. `v1` answers `["EMAIL"]` and `v2`
    answers `["EMAIL","SMS"]`, so you can tell from the body which one replied.
  - `tester` — a client pod with `curl`.
- **Deliberately conflicting routing** (`manifests/broken-config.yaml`): a
  `DestinationRule` with subsets `v1` and `v2`, a `VirtualService` whose
  catch-all route sits above its header rule, and a second `VirtualService`
  claiming the same host.

## Things to try

- Fix only the rule order, leaving both `VirtualService` objects in place, and
  send the header request repeatedly. Decide for yourself whether the result is
  something you would ship.
- Delete `notification-extra` first instead, and watch which symptom moves.
- Diff `istioctl proxy-config routes deploy/tester -n conflict-demo -o json`
  before and after each change — the route table is the only account of what
  actually happened.
- Give the second `VirtualService` a different host and re-run
  `istioctl analyze`; the `IST0109` warning should disappear.
- Add a third rule matching `uri: prefix: /notify` and place it below the
  catch-all, then confirm from the route table that it never appears.
