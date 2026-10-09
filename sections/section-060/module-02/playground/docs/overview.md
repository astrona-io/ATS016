# Overview: Troubleshoot With Prometheus And Grafana (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio, the Prometheus and Grafana add-ons and the starting workloads, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH.
- The **Prometheus** and **Grafana** add-ons from the Istio 1.30 release, in `istio-system`. Prometheus scrapes the metrics every sidecar proxy exposes on port `15090` and answers PromQL queries at `http://prometheus.istio-system:9090`. Grafana draws those metrics in Istio's bundled dashboards.
- Namespace **`metrics-demo`**, labelled `istio-injection=enabled`. Every pod shows `2/2`: the application container plus its `istio-proxy` sidecar proxy (Envoy).

  | Workload | What it is |
  | --- | --- |
  | `notification-service-v1` | Deployment behind the Service `notification-service` on port `80`; it answers `["EMAIL"]` |
  | `tester` | Client pod with `curl`; send test requests and Prometheus queries from here |

- **No traffic and no Istio routing objects at startup.** Every dashboard starts empty.

To open the web pages, forward their ports with `kubectl -n istio-system port-forward svc/grafana 3000:3000` or `kubectl -n istio-system port-forward svc/prometheus 9090:9090`, then open `http://localhost:3000` or `http://localhost:9090`. Whether that works depends on how you are connected to the playground. The helpers below query Prometheus from inside the cluster, which always works.

## Helpers

Paste these once in each new terminal. `prom_query` sends a PromQL query to Prometheus from the `tester` pod. `start_load` starts a background loop in the `tester` pod that sends about ten `POST` requests a second to `notification-service`. `stop_load` stops it.

```sh
prom_query() { kubectl -n metrics-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' --data-urlencode "query=$1"; echo; }
start_load() {
  kubectl -n metrics-demo exec deploy/tester -- sh -c \
    'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.1; done" >/dev/null 2>&1 &'
}
stop_load() {
  kubectl -n metrics-demo exec deploy/tester -- pkill -f 'while true' || true
}
```

Use them like this: `start_load`, `prom_query 'sum(rate(istio_requests_total[1m])) by (reporter)'`, `stop_load`.

## Practice tasks

- Run `start_load`, write a `VirtualService` for `notification-service` that aborts 30% of requests with a `500` and delays 50% by 500ms, and check both percentages with PromQL instead of counting `curl` output.
- Query the error ratio with `reporter="source"` and with `reporter="destination"`, and explain every difference you find.
- Group the client-side errors `by (response_flags)` and name the flag for an injected abort.
- Remove `by (le)` from a `histogram_quantile` query and read the `warnings` field in the response.
- Scale `notification-service-v1` to three replicas and group a rate `by (pod)` to see how the load spreads across pods.
- Open the Istio Control Plane dashboard, then restart `istiod` and watch the push metrics react.
- Open any Grafana panel in the Explore view and read the PromQL behind it.
