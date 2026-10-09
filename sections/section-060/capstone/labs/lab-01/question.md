# Question

Solve this question on: `terminal`

**Time:** about 40 minutes · **Exam topic:** Troubleshooting Configuration / the Mesh Data Plane

## Scenario

A team reports that `notification-service` in the namespace `obscapstone-demo` "fails sometimes". Somebody opened Kiali (the Istio console that draws the mesh as a graph), saw an empty graph, and escalated it as a total outage. Prometheus, Kiali and Grafana are all installed in `istio-system`.

Nobody has measured anything.

The namespace runs `notification-service-v1` behind the Service `notification-service` on port `80`, and a `tester` client pod with `curl`. Prometheus answers inside the cluster at `http://prometheus.istio-system:9090`.

## Your task

1. Explain why the graph is empty, and make it non-empty. The mesh is not down.
2. **Measure** the failure with PromQL instead of by counting `curl` output: the error ratio, and which side of the connection records the errors. Be able to say what the difference between `reporter="source"` and `reporter="destination"` proves about where the failure lives.
3. Find and fix every configuration fault in the namespace. There is more than the obvious one, and `istioctl analyze` names them.
4. Declare access logging for the namespace with a `Telemetry` object that uses the `envoy` provider, so the next person has an access log line for each request as well as metrics.
5. Prove with a query that the error ratio has returned to zero.

## Constraints

- Do not uninstall or reinstall the addons.
- **Do not invent a subset.** Any subset a `DestinationRule` defines must select at least one running pod.
- Exactly one `VirtualService` may claim `notification-service` on the mesh gateway when you are done.
- Leave the namespace serving traffic.

## Done when

- The Prometheus, Kiali and Grafana pods are all `Running`.
- A `Telemetry` object in `obscapstone-demo` enables the `envoy` access log provider.
- No fault injection remains anywhere in the namespace, and ten consecutive `POST` requests from `tester` return `200`.
- `istioctl analyze -n obscapstone-demo` reports no `Error` or `Warning` messages, and exactly one `VirtualService` claims `notification-service` on the mesh gateway. The mesh gateway is the built-in gateway name `mesh`, which stands for all sidecar proxies; a `VirtualService` with no `gateways` field applies to it.
- Every subset a `DestinationRule` defines selects at least one running pod.
