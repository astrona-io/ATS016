# Overview: Debug A 503 Caused By An mTLS Mismatch (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH. Access logging is on, which this module depends on.
- The injected namespace **`mtlsfail-demo`**, containing
  `notification-service-v1` behind the Service `notification-service` on port
  80, and a `tester` client pod with `curl`.
- **A live mTLS mismatch** (`manifests/broken-config.yaml`): a namespace-wide
  `PeerAuthentication` in `STRICT` mode, and a `DestinationRule` setting
  `trafficPolicy.tls.mode: DISABLE`. Every request fails.

## Things to try

- Read both proxies' logs before touching anything, and confirm the destination
  is silent. That absence is the diagnosis.
- Fix it from the wrong end — set the `PeerAuthentication` to `PERMISSIVE` —
  then check `connection_security_policy` in the destination's metrics. Traffic
  works and is not encrypted.
- Delete the `DestinationRule` entirely and confirm mTLS still happens. Nothing
  is required for sidecar-to-sidecar encryption.
- Reverse the mismatch: `PeerAuthentication` `DISABLE` with the client on
  `ISTIO_MUTUAL`. Compare the flags and the two logs against the original.
- Create an uninjected pod in another namespace and call the `STRICT` service
  from it. Same signature, different fix.
- Try `tls.mode: MUTUAL` without supplying certificates and read how that
  failure differs.
