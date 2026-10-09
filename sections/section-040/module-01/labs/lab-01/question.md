# Question

Solve this question on: `terminal`

**Time:** about 25 minutes · **Weight:** Troubleshooting the Mesh Data Plane

## Scenario

The namespace `proxycfg-demo` runs two versions of `notification-service` behind one Service. `v1` answers `["EMAIL"]`; `v2` answers `["EMAIL","SMS"]`. There is no Istio traffic configuration at all, so requests are spread across both versions:

```sh
kubectl -n proxycfg-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
```

## Your task

In the namespace `proxycfg-demo`:

1. Define subsets `v1` and `v2` over the pods' `version` label.
2. Route requests carrying the header `testing: true` to `v2`, and everything else to `v1`.
3. **Check the result in the proxy's own configuration**, not only in the responses. This is what the task really tests. For the `tester` proxy, be able to name the listener that catches the traffic, the route configuration it hands off to, the cluster each rule selects, and the endpoints that cluster resolves to.

## Constraints

- The header match must be an **exact** match on the value `true`.
- The catch-all route must come **after** the header rule.
- Both subsets must resolve to at least one healthy endpoint. A subset whose labels match no pod is not a valid answer.
- Do not change the Deployments, the Service or the `tester` pod.

## Done when

- A `DestinationRule` for `notification-service` defines `v1` and `v2` over the `version` label (`version: v1` and `version: v2`).
- In the `tester` proxy's route table for port 80, the first route matches the header `testing` exactly on `true` and sends it to the `v2` cluster, and the last route sends everything else to the `v1` cluster.
- `istioctl proxy-config endpoint` shows at least one `HEALTHY` endpoint for both subset clusters.
