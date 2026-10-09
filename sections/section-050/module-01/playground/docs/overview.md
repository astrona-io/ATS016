# Overview: Read Envoy Access Logs And Response Flags (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy ats-016-playground-050-01`, start over.

## What is in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH. That profile already enables access logging mesh-wide.
- The injected namespace **`accesslog-demo`**, containing
  `notification-service-v1` behind the Service `notification-service` on port
  80, and a `tester` client pod with `curl`.
- A `Telemetry` object (`manifests/telemetry.yaml`), the flight log settings,
  scoping access logging to this namespace. It is not needed under the `demo` profile and is applied so you
  can see the object that does the scoping in a real install.
- Three manifests in the playground folder that each produce a different failure:
  - `fault-timeout.yaml`: a 5s delay against a 1s timeout, meant for `UT`.
    The fault filter runs before the router, so the timeout may never see the
    delay; if you get a `200` with the flag `DI` instead, that is why.
  - `circuit-breaker.yaml`: a connection pool of one, for `UO`.
  - `deny-all.yaml`: a deny-all `AuthorizationPolicy`, for an RBAC `403` on the
    destination proxy.

  The course parts show the same YAML on the page, to save as a file and apply
  yourself.

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
