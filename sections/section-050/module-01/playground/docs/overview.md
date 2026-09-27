# Overview: Read Envoy Access Logs And Response Flags (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH. That profile already enables access logging mesh-wide.
- The injected namespace **`accesslog-demo`**, containing
  `notification-service-v1` behind the Service `notification-service` on port
  80, and a `tester` client pod with `curl`.
- A `Telemetry` object (`manifests/telemetry.yaml`) scoping access logging to
  this namespace. It is redundant under the `demo` profile and is applied so you
  can see the object that does the scoping in a real install.
- Four manifests that each produce a different failure, ready to apply:
  - `fault-timeout.yaml` — a 5s delay against a 1s timeout, for `UT`.
  - `circuit-breaker.yaml` — a connection pool of one, for `UO`.
  - `deny-all.yaml` — a deny-all `AuthorizationPolicy`, for an RBAC `403` on the
    destination proxy.

Traffic starts healthy. Every failure here is one you apply yourself.

## Things to try

- Apply one failure manifest at a time and predict the flag before reading the
  log. Remove it before applying the next; they interfere.
- Send a request and read both proxies' logs side by side. Work out, from the
  pair alone, whether it crossed the network.
- Stop the destination mid-request (`kubectl scale ... --replicas=0` during a
  loop) and find `UC` or `UF`.
- Add a `filter` to the `Telemetry` object so only non-200 responses are logged,
  then generate both kinds of traffic.
- Change `meshConfig.accessLogFormat` through the install, or set a JSON format
  in the `Telemetry` provider, and compare readability.
