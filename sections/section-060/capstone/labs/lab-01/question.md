# Capstone: Measure A Failure, Fix It, Prove It

**Time:** about 40 minutes · **Weight:** Troubleshooting Configuration / the Mesh Data Plane
**Covers:** modules 1–2 (Kiali, Prometheus and Grafana)

## Scenario

A team reports that `notification-service` in `obscapstone-demo` "fails
sometimes". Somebody opened Kiali, saw an empty graph, and escalated it as a
total outage. Prometheus, Kiali and Grafana are all installed.

Nobody has measured anything.

## Your task

1. Explain why the graph is empty, and make it non-empty. The mesh is not down.
2. **Measure** the failure with PromQL rather than by counting `curl` output:
   the error ratio, and which side of the connection records the errors. Be able
   to say what the `reporter` asymmetry proves about where the failure lives.
3. Find and fix every configuration fault in the namespace. There is more than
   the obvious one, and `istioctl analyze` names them.
4. Declare access logging for the namespace with a `Telemetry` object, so the
   next person has per-request evidence as well as metrics.
5. Prove with a query that the error ratio has returned to zero.

## Constraints

- Do not uninstall or reinstall the addons.
- **Do not invent a subset.** Any subset a route names must select at least one
  running pod.
- Exactly one `VirtualService` may claim `notification-service` on the mesh
  gateway when you are done.
- Leave the namespace serving traffic.

## Done when

- Prometheus, Kiali and Grafana pods are all `Running`.
- A `Telemetry` object in `obscapstone-demo` enables the `envoy` access log
  provider.
- No fault injection remains anywhere in the namespace, and ten consecutive
  requests return `200`.
- `istioctl analyze -n obscapstone-demo` reports no findings.
