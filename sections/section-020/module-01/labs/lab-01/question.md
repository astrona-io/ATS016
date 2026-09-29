# Task: Make The Header Route Actually Fire

**Time:** about 20 minutes · **Weight:** Troubleshooting Configuration

## Scenario

`notification-service` in the namespace `conflict-demo` runs two versions. `v1`
answers `["EMAIL"]`; `v2` answers `["EMAIL","SMS"]`.

The intent is simple and somebody already wrote it: a request carrying the
header `testing: true` should reach `v2`, and everything else should reach `v1`.
It does not happen — every request reaches `v1`:

```sh
kubectl -n conflict-demo exec deploy/tester -- sh -c \
  'curl -s -X POST -H "testing: true" http://notification-service/notify; echo'
```

`istioctl analyze` reports nothing more serious than a `Warning`.

## Your task

In the namespace `conflict-demo`:

1. Work out why the header rule never fires. There are **two** independent
   causes, and fixing only one is not enough.
2. Repair the routing so the intent holds.

## Constraints

- **Exactly one `VirtualService` may claim the `notification-service` host** on
  the mesh gateway when you are done.
- Do not modify the `DestinationRule`, the Deployments, the Service or the
  `tester` pod.
- Do not change how the versions respond — the response body is the evidence.

## Done when

- Ten consecutive requests carrying `testing: true` all return `["EMAIL","SMS"]`.
- Ten consecutive requests without the header all return `["EMAIL"]`.
- `kubectl -n conflict-demo get virtualservice` shows one object claiming the
  host, and `istioctl analyze -n conflict-demo` is clean.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
