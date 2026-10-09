# Troubleshoot With Prometheus And Grafana

Astronaut, a few `curl` commands tell you whether a service is broken right now. They cannot tell you that failures started at 14:05, that they hit 30% of signals and not all of them, that the client sees more errors than the server, or that the slow requests are slow by exactly half a second.

That is what this module is about. Logs and `istioctl proxy-config` answer questions about **this request** and **this proxy**. Metrics answer questions about **all requests over time**: how much, how bad, how slow, since when, and for whom. Every communications officer (sidecar proxy) in the mesh counts the signals it handles, with no change to any application. Prometheus is the telemetry recorder that collects those counts, and Grafana is the set of dashboard screens in mission control that shows them. This module covers the metrics that matter, the labels that make them useful, and the queries worth knowing by heart.

## Learning objectives

After this module you can:

- Describe how a proxy's metrics reach Prometheus, and what breaks that path.
- Name Istio's standard request metrics and the questions each one answers.
- Explain why the raw value of a counter means nothing, and what to read instead.
- Use the `reporter` label to compare the client's view of traffic with the server's, and explain a difference between them.
- Write PromQL (the Prometheus query language) for a request rate, an error ratio and a latency percentile.
- Explain why `le` must survive the aggregation in a histogram query.
- Query Prometheus without a browser, and read the same numbers directly from a proxy.
- Check an injected failure against the percentage you injected.
- Say which of Istio's four Grafana dashboards to open for a given question.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels and `kubectl exec`.
- **Istio basics.** What a sidecar proxy is, and what a `VirtualService` does.
- **Response flags.** When a request fails, the proxy writes a short code next to it, such as `UH` (no healthy upstream), `UF` (upstream connection failure), `UO` (overflow, a circuit breaker) or `UT` (timeout). It is the code the communications officer stamps on a failed signal in the flight log (the access log). Here the same code appears as a metric label.
- **PromQL is optional.** Every query is explained when it first appears.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** already installed (the `demo` profile) and `istioctl` ready to use. In the `istio-system` namespace it also runs the **Prometheus** and **Grafana** add-ons, with Istio's four bundled Grafana dashboards.

The planet (namespace) **`metrics-demo`** has sidecar injection switched on. On it you find:

| Workload | What it does |
| --- | --- |
| `notification-service-v1` | The app, behind the Service (beacon) `notification-service` on port `80`. It answers `["EMAIL"]` |
| `tester` | Your test ship, with `curl`. Every test signal and every Prometheus query is sent from here |

No traffic flows at startup, so every dashboard starts empty.

Prometheus and Grafana are web pages. Whether your browser can reach them depends on how you are connected to the playground. So the hands-on steps query Prometheus over its HTTP interface from inside the cluster: same data, same queries, no browser needed.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts, in order

1. [The Metrics Pipeline](./course-01-the-metrics-pipeline.md): where the numbers come from, port `15090` and scraping, the metrics and labels, and why counters and histograms are read differently.
2. [The reporter Label And PromQL Patterns](./course-02-reporter-and-promql.md): two counts of every request, what a difference between them proves, and the three query shapes that cover most troubleshooting.
3. [Measuring A Known Failure](./course-03-measuring-a-known-failure.md): injecting a known error rate and delay, measuring both with PromQL, and reading the difference between the client's and the server's view.
4. [Grafana, Flight Logs And Proving The Fix](./course-04-grafana-and-proving-the-fix.md): which bundled dashboard answers which question, asking for access logs with a `Telemetry` object, and proving the fault is gone.
5. [Wrap-Up: Mission Debrief](./course-05-wrap-up.md): what you learned, your mission, and cleaning up.

## Why this matters

Metrics answer questions nothing else can:

- **Is this really broken, or did you catch one bad request?** An error ratio settles it in one query.
- **When did it start?** Counters have history. The end of an access log does not.
- **Who is affected?** `by (source_workload)` turns "the service is failing" into a list of callers.
- **Is it slow, or is it failing?** The duration histogram and the response code counter answer different questions, and people often mix them up.

In an incident, use Grafana or Kiali to find *where*, metrics to learn *how much and since when*, then the access log and `istioctl proxy-config` to find *why*.
