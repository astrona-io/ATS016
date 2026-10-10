# Troubleshoot With Prometheus And Grafana

A few `curl` commands tell you whether a service is broken right now. They cannot tell you that failures started at 14:05, that they hit 30% of requests and not all of them, that the client sees more errors than the server, or that the slow requests are slow by about half a second.

Metrics answer those questions. Logs and `istioctl proxy-config` answer questions about **this request** and **this proxy**. Metrics answer questions about **all requests over time**: how many, how bad, how slow, since when, and for whom. Every sidecar proxy in the mesh counts the requests it handles, with no change to any application. Prometheus is the monitoring system that collects those counts and stores them as time series, and Grafana is the dashboard tool that draws them as graphs.

The module has four parts. **The Metrics Pipeline** follows a number from the proxy to Prometheus and explains the metrics, the labels, and why counters and histograms are read differently. **The reporter Label And PromQL Patterns** shows that every request is counted twice, what a difference between the two counts proves, and the three query shapes that cover most troubleshooting. **Measuring A Known Failure** injects a known error rate and delay and checks each query against it; a graded lab follows it. **Grafana, Access Logs And Proving The Fix** covers the bundled dashboards, turns on access logs for one namespace with a `Telemetry` object, and proves that the fault is gone; a second graded lab follows it.

## Learning objectives

After this module you can:

- Describe how a proxy's metrics reach Prometheus, and what breaks that path.
- Name Istio's standard request metrics and the questions each one answers.
- Explain why the raw value of a counter means nothing, and what to read instead.
- Use the `reporter` label to compare the client's view of traffic with the server's, and explain a difference between them.
- Write PromQL for a request rate, an error ratio and a latency percentile.
- Explain why `le` must survive the aggregation in a histogram query.
- Query Prometheus without a browser, and read the same numbers directly from a proxy.
- Check an injected failure against the percentage you injected, and find which caller it affects.
- Say which of Istio's Grafana dashboards to open for a given question.

## Before you start

You need Kubernetes basics: namespaces, Deployments, Services, pod labels and `kubectl exec`. You also need two Istio basics. A sidecar proxy (Envoy) is a proxy container that Istio adds to each pod; all inbound and outbound traffic of the pod passes through it. A `VirtualService` is the Istio resource that tells the sidecar proxies how to route requests for a host.

It helps to know response flags. When a request fails, the sidecar proxy writes a short Envoy code next to it in the access log, such as `UH` (no healthy upstream), `UF` (upstream connection failure), `UO` (upstream overflow, from a circuit breaker) or `UT` (upstream request timeout). In this module the same code appears as a metric label. PromQL, the Prometheus query language, is not needed in advance: every query is explained when it first appears.

Your playground is one `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` on your PATH. The `istio-system` namespace also runs the **Prometheus** and **Grafana** add-ons, with Istio's bundled Grafana dashboards. The namespace **`metrics-demo`** has sidecar injection switched on and runs these workloads:

| Workload | What it is |
| --- | --- |
| `notification-service-v1` | A Deployment behind the Service `notification-service` on port `80`. It answers `["EMAIL"]` |
| `tester` | A client pod with `curl`. Every test request and every Prometheus query is sent from here |

No traffic flows at startup, so every dashboard starts empty. Prometheus and Grafana are web pages, and whether your browser can reach them depends on how you are connected to the playground. So the hands-on steps query Prometheus over its HTTP interface from inside the cluster: the same data and the same queries, with no browser needed.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
