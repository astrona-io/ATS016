# Overview: Troubleshoot With Prometheus And Grafana (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs `bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What is in the box

- A single-node `kind` Kubernetes cluster (your training solar system) with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your PATH.
- The **Prometheus and Grafana add-ons** from the Istio 1.30 release, in `istio-system`, with Istio's four bundled dashboards. Prometheus is the telemetry recorder; Grafana is the dashboard screens.
- The injected namespace **`metrics-demo`**, containing `notification-service-v1` behind the Service `notification-service` on port `80`, and a `tester` client pod with `curl`.

No traffic flows at startup, so every dashboard starts empty.

The course pages give you the YAML for the fault drill used in this module: a `VirtualService` that aborts 30% of requests with a `500` and delays 50% of them by 500ms, so both the counter and the histogram have something to show. Save it to a file and apply it with `kubectl apply -f`.

## Reaching the dashboards

```sh
kubectl -n istio-system port-forward svc/grafana 3000:3000
kubectl -n istio-system port-forward svc/prometheus 9090:9090
```

Then open `http://localhost:3000` or `http://localhost:9090` in a browser that can reach this machine. Whether that works depends on how you are connected to the playground. Every exercise in the module also queries Prometheus over its HTTP interface from inside the cluster, which always works:

```sh
kubectl -n metrics-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' \
  --data-urlencode 'query=sum(rate(istio_requests_total[1m])) by (reporter)'
```

## Things to try

- Generate load, apply the fault drill, and check the injected percentages with PromQL instead of counting `curl` output.
- Query the same thing with `reporter="source"` and `reporter="destination"`, and explain every difference you find.
- Drop `by (le)` from the `histogram_quantile` query and see how confidently wrong the answer is.
- Scale the Deployment to three replicas and group a rate `by (destination_workload, pod)` to see uneven load per pod.
- Open the Istio Control Plane dashboard, then scale `istiod` and watch the push metrics react.
- Use Grafana's Explore view on any panel to read the PromQL behind it.
