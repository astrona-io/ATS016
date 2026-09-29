# Task: Build The Routing, Then Prove It From The Proxy

**Time:** about 25 minutes · **Weight:** Troubleshooting the Mesh Data Plane

## Scenario

`proxycfg-demo` runs two versions of `notification-service` behind one Service.
`v1` answers `["EMAIL"]`; `v2` answers `["EMAIL","SMS"]`. There is no Istio
traffic configuration at all, so requests are load balanced across both:

```sh
kubectl -n proxycfg-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
```

## Your task

In the namespace `proxycfg-demo`:

1. Define subsets `v1` and `v2` over the pods' `version` label.
2. Route requests carrying the header `testing: true` to `v2`, and everything
   else to `v1`.
3. **Verify the result from the proxy's own configuration**, not only from
   responses — this is what the task is really testing. Be able to name, for the
   `tester` proxy: the listener that captures the traffic, the route
   configuration it hands off to, the cluster each rule selects, and the
   endpoints that cluster resolves to.

## Constraints

- The header match must be an **exact** match on the value `true`.
- The catch-all route must come **after** the header rule.
- Both subsets must resolve to at least one healthy endpoint — a subset whose
  labels match no pod is not a valid answer.
- Do not modify the Deployments, the Service or the `tester` pod.

## Done when

- A `DestinationRule` defines `v1` and `v2` over the `version` label.
- The `tester` proxy's route table sends the header case to the `v2` cluster and
  everything else to `v1`.
- `istioctl proxy-config endpoint` shows at least one `HEALTHY` endpoint for
  both subset clusters.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
