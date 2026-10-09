# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about metrics: the counts every communications officer keeps, Prometheus as the telemetry recorder, and Grafana as the dashboard screens in mission control.

**From [The Metrics Pipeline](./course-01-the-metrics-pipeline.md):**

- The proxy counts every request, shows the numbers on port `15090`, Prometheus scrapes them about every 15 seconds, and tools query Prometheus.
- No sidecar means no metrics. TCP traffic appears in `istio_tcp_*`, not in `istio_requests_total`.
- The labels on `istio_requests_total` name the caller, the callee, the result, the response flag and the encryption.
- Counters only go up: read them with `rate()`. Histograms count into cumulative `le` buckets, and a percentile from them is an estimate.

**From [The reporter Label And PromQL Patterns](./course-02-reporter-and-promql.md):**

- Every request is counted twice: `reporter="source"` by the client proxy and `reporter="destination"` by the server proxy.
- Adding up both reporters doubles the rate. A difference between them is a finding.
- The three query shapes: a grouped rate, a ratio, and a percentile with `histogram_quantile(... by (le))`.
- Dropping `le` gives a meaningless answer with no error.

**From [Measuring A Known Failure](./course-03-measuring-a-known-failure.md):**

- A fault drill gives a known answer, so you can check your query against it.
- An abort injected by the client proxy shows up in `source` only. The destination never sees those requests.
- A delayed success is still a `200`. Delay shows only in the duration histogram.

**From [Grafana, Flight Logs And Proving The Fix](./course-04-grafana-and-proving-the-fix.md):**

- Istio Mesh for the whole mesh, Istio Service for client and server side by side, Istio Workload for inbound and outbound, Istio Control Plane for `istiod`.
- A `Telemetry` object with the `envoy` provider turns access logging on for one namespace.
- Prove a fix with the same query that measured the failure, after the window has passed. Counters keep their totals, and rates forget.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Measure The Failure Before You Fix It](./labs/lab-01/README.md) | Grafana, Flight Logs And Proving The Fix | measure a failure with PromQL, remove the fault, declare access logging, and prove success in Prometheus |

If you skipped it, go back to it now. It is short.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. A dashboard shows no data for one workload. What is the first thing to check?</summary>

Whether the workload's proxy has the metric at all, with `pilot-agent request GET stats/prometheus` in its `istio-proxy` container. If there is no sidecar, there are no metrics anywhere.
</details>

<details>
<summary>2. <code>istio_requests_total</code> for a workload reads <code>4213</code>. What does that tell you?</summary>

Almost nothing. A counter only goes up, so the raw value mostly reflects how long the proxy has been running. Read its `rate()` instead.
</details>

<details>
<summary>3. Your request rate looks twice as high as expected. What is the likely mistake?</summary>

You added up both reporters. Every request is counted by the client proxy and the server proxy. Filter on one `reporter`.
</details>

<details>
<summary>4. Errors appear with <code>reporter="source"</code> but not with <code>reporter="destination"</code>. Where is the failure?</summary>

In the client's proxy or on the path between the two. The requests never reached the destination, for example because of an injected abort, a circuit breaker or a connection failure.
</details>

<details>
<summary>5. A <code>histogram_quantile</code> query returns <code>NaN</code>. What did you probably leave out?</summary>

`by (le)` in the inner `sum`. Without the bucket edge label, `histogram_quantile` cannot find the buckets and gives a meaningless answer.
</details>

<details>
<summary>6. Half the requests are delayed by 500ms, but the error ratio is zero. Why?</summary>

A delayed request that succeeds is still a `200`. Delay only shows in `istio_request_duration_milliseconds_bucket`.
</details>

<details>
<summary>7. Which Grafana dashboard shows what a workload calls, as well as who calls it?</summary>

Istio Workload. It has both inbound and outbound panels.
</details>

<details>
<summary>8. You removed a fault, and the error ratio is still above zero. Is the fix wrong?</summary>

Not yet known. A `[1m]` rate still holds samples from before the fix. Wait at least a full window, with traffic still flowing, then measure again.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-060-02
```

If `astrona list` also showed the mission, remove it the same way:

```sh
astrona destroy ats-016-lab-060-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with `astrona run`. It always starts clean, so nothing you broke carries over.

> *Measure first, fix second, and prove it with the same query: that is how a "sometimes" becomes a number.*
