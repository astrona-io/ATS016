# Question

Solve this question on: `terminal`

Astronaut, a flight plan on the planet `conflict-demo` never does what it says. Istio 1.30.5 is installed.

`notification-service` in the namespace `conflict-demo` runs two versions. `v1` answers `["EMAIL"]` and `v2` answers `["EMAIL","SMS"]`, so the reply tells you which version answered.

The plan is simple, and somebody already wrote it: a request carrying the header `testing: true` should reach `v2`, and everything else should reach `v1`. It does not happen. Every request reaches `v1`:

```sh
kubectl -n conflict-demo exec deploy/tester -- sh -c \
  'curl -s -X POST -H "testing: true" http://notification-service/notify; echo'
```

`istioctl analyze` reports nothing more serious than a `Warning`.

## Your task

In the namespace `conflict-demo`:

1. Work out why the header rule never fires. There are **two** separate causes, and fixing only one is not enough.
2. Repair the routing so the plan holds.

## Constraints

- **Exactly one `VirtualService` may claim the `notification-service` host** on the mesh gateway (no `gateways:` field, or `mesh`) when you are done.
- Do not change the `DestinationRule`, the Deployments, the Service or the `tester` pod.
- Do not change how the versions answer. The reply body is the evidence.

## Done when

- Ten requests in a row carrying `testing: true` (`POST http://notification-service/notify` from the `tester` pod) all return `["EMAIL","SMS"]`.
- Ten requests in a row without the header all return `["EMAIL"]`.
- `kubectl -n conflict-demo get virtualservice` shows one object claiming the host, and `istioctl analyze -n conflict-demo` no longer reports `IST0109`.
