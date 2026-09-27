# Overview: Troubleshoot With Prometheus And Grafana (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH.
- The **Prometheus and Grafana addons** from the Istio 1.30 release, in
  `istio-system`, with Istio's four bundled dashboards.
- The injected namespace **`metrics-demo`**, containing
  `notification-service-v1` behind the Service `notification-service` on port
  80, and a `tester` client pod with `curl`.
- `manifests/fault.yaml` — aborts 30% of requests with a `500` and delays 50% of
  them by 500ms, so both the counter and the histogram have something to show.

No traffic is flowing at startup, so every dashboard starts empty.

## Reaching the UIs

```sh
kubectl -n istio-system port-forward svc/grafana 3000:3000
kubectl -n istio-system port-forward svc/prometheus 9090:9090
```

Then open `http://localhost:3000` or `http://localhost:9090` from a browser that
can reach this machine. Whether that works depends on how you are connected to
the playground; every exercise in the module also queries Prometheus over its
HTTP API from inside the cluster, which always works:

```sh
kubectl -n metrics-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' \
  --data-urlencode 'query=sum(rate(istio_requests_total[1m])) by (reporter)'
```

## Things to try

- Generate load, apply `fault.yaml`, and verify the injected percentages with
  PromQL rather than by counting `curl` output.
- Query the same thing with `reporter="source"` and `reporter="destination"`
  and explain every difference you find.
- Drop `by (le)` from the `histogram_quantile` query and see how confidently
  wrong the answer is.
- Scale the Deployment to three replicas and group a rate
  `by (destination_workload, pod)` to see per-pod skew.
- Open the Istio Control Plane dashboard, then scale `istiod` and watch the
  push metrics react.
- Use Grafana's Explore view on any panel to read the PromQL behind it.
