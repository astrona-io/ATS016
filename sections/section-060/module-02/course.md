# Troubleshoot With Prometheus And Grafana

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-060/module-02/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-060/module-02/playground
> astrona destroy ats-016-playground-060-02
> ```

Counting `curl` output tells you whether a service is broken right now. It cannot tell you that failures started at 14:05, that they affect 30% of requests rather than all of them, that the client sees more errors than the server does, or that the slow requests are slow by exactly half a second.

That is the contrast this module turns on. Logs and `proxy-config` answer questions about **this request** and **this proxy**; metrics answer questions about **all requests over time** — how much, how bad, how slow, since when, and for whom. Istio's sidecars export the data for every workload in the mesh with no change to any application, and this module is the handful of metrics that matter, the labels that make them useful, and the queries worth knowing by heart.

> Istio's standard metrics answer how much, how bad and how slow, split by source and destination, without touching the application.

## How this module is organised

1. **[Part 1 — The Metrics Pipeline](./course-01-the-metrics-pipeline.md)** — where the numbers come from, port 15090 and scraping, the metric and label inventory, and why counters and histograms are read differently.
2. **[Part 2 — The reporter Label And PromQL Patterns](./course-02-reporter-and-promql.md)** — two independent observations of every request, what a disagreement between them proves, and the three query shapes that cover most troubleshooting.
3. **[Part 3 — Measuring A Known Failure, And Grafana](./course-03-measuring-a-failure-and-grafana.md)** — injecting a known error rate and delay, measuring both with PromQL, reading the client/server asymmetry, and which bundled dashboard answers which question.

## Learning objectives

After this module you can:

- Describe how a proxy's metrics reach Prometheus, and what breaks the pipeline.
- Name Istio's standard request metrics and the questions each one answers.
- Explain why a counter's absolute value is meaningless and what to read instead.
- Use the `reporter` label to compare the client's view of traffic with the server's, and interpret a disagreement.
- Write PromQL for a request rate, an error ratio and a latency percentile.
- Explain why `le` must survive aggregation in a histogram query.
- Query Prometheus without a browser, and read the same numbers directly from a proxy.
- Verify an injected failure against the percentage you injected.
- Say which of Istio's four Grafana dashboards to open for a given question.

## Before you start

You need [section 050](../../section-050/module-01/course.md) — response flags appear here as a metric label, and this module assumes you know what they mean. Some familiarity with PromQL helps but is not required; every query is explained as it appears.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, the **Prometheus and Grafana addons** in `istio-system`, and the injected namespace **`metrics-demo`** containing `notification-service-v1` behind a Service on port 80 and a `tester` client pod with `curl`.

Prometheus and Grafana are web UIs, and reaching them from a browser needs a port-forward your browser can connect to — which depends on how you are connected to this playground. The checkpoints therefore query Prometheus over its HTTP API from inside the cluster: same data, same queries, no browser required.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it.

## Where this fits

Metrics answer a different class of question from everything else in this course:

- **Is this actually broken, or did you catch one bad request?** An error ratio settles it in one query.
- **When did it start?** Counters have history; an access log tail does not.
- **Who is affected?** `by (source_workload)` turns "the service is erroring" into a list of callers.
- **Is it slow, or is it failing?** The duration histogram and the response-code counter are different questions, often confused.

The natural order in an incident is: Grafana or Kiali to find *where*, metrics to establish *how much and since when*, then the access log and `proxy-config` to find *why*.
