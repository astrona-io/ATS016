# Question

Solve this question on: `terminal`

**Time:** about 25 minutes · **Exam topic:** Troubleshooting Configuration

## Scenario

Kiali (the Istio console that draws the mesh as a graph) and Prometheus (the monitoring system it reads metrics from) are installed in `istio-system`. A colleague opened the Kiali graph for the namespace `kiali-demo`, saw nothing at all, and filed a ticket saying "the mesh is down".

Separately, Kiali's **Istio Config** view shows a red validation icon on one of the namespace's objects.

The namespace runs `notification-service-v1` behind the Service `notification-service` on port `80`, and a `tester` client pod with `curl`.

## Your task

In the namespace `kiali-demo`:

1. Explain why the graph is empty, and make it non-empty. The mesh is not down.
2. Find the object Kiali's validation view marks, and confirm the same messages from the command line. Then fix them so validation is clean.
3. Confirm both of Kiali's data sources are healthy, and be able to say what each one contributes.

## Constraints

- Do not uninstall or reinstall the addons.
- The remaining routing must still send traffic to `notification-service`. Do not fix the validation errors by deleting every routing object and leaving the namespace unrouted: at least one `VirtualService` for the host `notification-service` must remain.
- Any subset a route names must be defined and select at least one running pod.

## Done when

- The Prometheus and Kiali pods are `Running`.
- `istioctl analyze -n kiali-demo` reports no `Error` or `Warning` messages, and a `VirtualService` for `notification-service` still exists.
- The `tester` pod's sidecar proxy holds `istio_requests_total` series for requests from `tester` to `notification-service`, so the graph has an edge to draw.
