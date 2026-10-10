# Summary

Kiali shows the whole mesh on one screen, and it is easy to trust that picture too much. This module showed what Kiali is built from, how to read its graph, and how to check every picture it draws against the data underneath.

## What you learned

Kiali stores nothing. It reads Istio objects, Services and Pods from the Kubernetes API server, and request metrics from Prometheus, live on every page. Prometheus collects those metrics from each sidecar proxy on port `15090` about every 15 seconds. So the graph is empty when Prometheus is missing, when Kiali cannot reach it, when the workload has no sidecar, or simply when no requests were sent in the time window. To explain an empty graph, walk the path in order: send traffic, read the proxy's own metrics with `pilot-agent request GET stats/prometheus`, query Prometheus, then check Kiali's connection to Prometheus.

An edge in the graph is a `sum(rate(istio_requests_total[...]))` grouped by source and destination. The response codes decide its colour, and `connection_security_policy` decides the padlock. The graph type decides what a node is, so a canary problem visible in *versioned app* can vanish in *app*. An edge is a rate over a window, so it fades after traffic stops and changes slowly after a fix. The Workloads and Services lists come from the API server, so they show workloads that send no traffic.

A red edge says only that a significant share of requests between two workloads failed in the window. It does not say the callee is at fault. An abort from fault injection is created in the caller's sidecar proxy, so the destination never sees the request and its metrics never count the error. The graph locates the pair of workloads; the caller's access log and `istioctl proxy-config` explain the failure.

Kiali's Istio Config view runs the same analyzers as `istioctl analyze` and reports the same `IST####` codes. The padlock reports traffic that happened, not a policy that is required. The key facts to remember are these:

- No Prometheus, no graph; no traffic in the window, no graph either.
- `connection_security_policy` is `mutual_tls` on the destination's metrics and `unknown` on the caller's.
- Every picture in Kiali has a command behind it; check that command before you act on a surprise.
- The order of an investigation is the Kiali graph, the access log on the caller, `istioctl proxy-config`, then `istioctl analyze`.

<!-- astrona:playground:destroy -->
