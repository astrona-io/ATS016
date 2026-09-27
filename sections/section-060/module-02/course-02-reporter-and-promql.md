# Part 2 — The reporter Label And PromQL Patterns

> Prerequisite: [Part 1 — The Metrics Pipeline](./course-01-the-metrics-pipeline.md). Next: [Part 3 — Measuring A Known Failure, And Grafana](./course-03-measuring-a-failure-and-grafana.md).

Every request in the mesh is counted twice. That is not a defect to filter around — it is the metrics equivalent of reading both proxies' access logs, and the difference between the two counts is a diagnostic in its own right. This part covers that label, then the three query shapes that answer most troubleshooting questions.

## Two observations of one request

```text
   tester ──▶ [client proxy] ────────▶ [destination proxy] ──▶ notification-service
                    │                          │
                    │ counts it as             │ counts it as
                    │ reporter="source"        │ reporter="destination"
                    ▼                          ▼
              istio_requests_total       istio_requests_total
```

Both proxies increment the same metric name with the same labels except `reporter`. The readings:

| Comparison | Means |
| --- | --- |
| both agree | normal. Pick one and be consistent. |
| **source sees requests destination does not** | the request never arrived — the metrics form of the `UF`/`NC` signature ([module 050-02](../../section-050/module-02/course-02-the-signature.md)) |
| **source sees errors destination reports as success** | the failure was on the way back, or inside the client proxy: a timeout, a circuit breaker, a reset after the response started |
| destination sees requests source does not | the caller is not in the mesh — it has no proxy to count them |

That last row is quietly useful: it identifies unmeshed callers of a meshed service without touching a single pod.

And forgetting the label is the most common way to get a query wrong. A rate summed across both reporters is roughly **double** the true request rate, which makes every dashboard built on it wrong by a factor of two in a way nobody notices until they compare it with something else.

> [!TIP]
> **Try it — the same traffic, counted twice**
>
> First start a steady load so there is something to measure. It runs until the last checkpoint of [Part 3](./course-03-measuring-a-failure-and-grafana.md) stops it.
>
> ```sh
> kubectl -n metrics-demo exec deploy/tester -- sh -c \
>   'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.1; done" >/dev/null 2>&1 &'
> sleep 30
> kubectl -n metrics-demo exec deploy/tester -- curl -s \
>   'http://prometheus.istio-system:9090/api/v1/query' \
>   --data-urlencode 'query=sum(rate(istio_requests_total{destination_workload="notification-service-v1"}[1m])) by (reporter, response_code)'
> ```
>
> Expect something like:
>
> ```text
> {"status":"success","data":{"resultType":"vector","result":[
>   {"metric":{"reporter":"destination","response_code":"200"},"value":[1774000000,"9.8"]},
>   {"metric":{"reporter":"source","response_code":"200"},"value":[1774000000,"9.8"]}]}}
> ```
>
> Two series with near-identical rates — around ten requests per second each, which is **one** workload's traffic seen from both ends. They are rarely exactly equal: the two proxies are scraped at different instants, so a request in flight is counted by one and not yet the other.

## Query shape one: a rate, grouped

Almost every troubleshooting query in PromQL is the same three-part pattern:

```text
   sum(  rate(  metric{filters}[window]  )  ) by (labels)
    │      │           │         │              │
    │      │           │         │              └── what you want to compare
    │      │           │         └───────────────── how far back to average
    │      │           └─────────────────────────── which series to include
    │      └─────────────────────────────────────── counter → per-second change
    └────────────────────────────────────────────── collapse everything not in `by`
```

Applied to request rate by outcome:

```promql
sum(rate(istio_requests_total{destination_workload="notification-service-v1", reporter="destination"}[1m])) by (response_code)
```

Change the `by` clause to change the question, and it is worth knowing the four that matter most:

| `by (...)` | Answers |
| --- | --- |
| `response_code` | is it failing, and how |
| `source_workload` | **who** is affected — turns one alert into a blast radius |
| `response_flags` | *why* it is failing, in section 050's vocabulary |
| `destination_version` | is the canary worse than the stable version |

The `[1m]` window is a trade-off: short is responsive and noisy, long is smooth and slow to react. One minute is a reasonable default for interactive troubleshooting, five for dashboards.

## Query shape two: a ratio

An error ratio is two of the same query divided, and it is what an SLO is written against because it is independent of traffic volume:

```promql
sum(rate(istio_requests_total{reporter="destination", response_code=~"5.."}[1m]))
  /
sum(rate(istio_requests_total{reporter="destination"}[1m]))
```

`=~` is a regular-expression match, so `"5.."` means any three-character code beginning with `5`. The result is between 0 and 1.

Two things to keep right. **The filters on both halves must match** apart from the thing you are selecting for — a numerator scoped to one workload over a mesh-wide denominator produces a meaningless number. And **the `reporter` must be the same on both**, for the same reason.

## Query shape three: a percentile

```promql
histogram_quantile(0.99,
  sum(rate(istio_request_duration_milliseconds_bucket{destination_workload="notification-service-v1"}[1m])) by (le))
```

Read it inside out: take the bucket counters, rate them, sum them **keeping `le`**, then interpolate the 99th percentile.

`le` is the bucket boundary label from [Part 1](./course-01-the-metrics-pipeline.md), and it **must survive the aggregation**. `histogram_quantile` needs the full set of buckets to find which one the target rank falls in; drop `le` and you hand it a single meaningless number, from which it will produce a confident, meaningless answer. No error is raised. This is the classic PromQL mistake and it is silent.

To compare percentiles across workloads, add the grouping label alongside `le`:

```promql
histogram_quantile(0.99,
  sum(rate(istio_request_duration_milliseconds_bucket[1m])) by (le, destination_workload))
```

> [!TIP]
> **Try it — the three shapes, and the mistake**
>
> ```sh
> Q() { kubectl -n metrics-demo exec deploy/tester -- curl -s \
>   'http://prometheus.istio-system:9090/api/v1/query' --data-urlencode "query=$1"; echo; }
>
> Q 'sum(rate(istio_requests_total{destination_workload="notification-service-v1",reporter="destination"}[1m])) by (response_code)'
> Q 'histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{destination_workload="notification-service-v1"}[1m])) by (le))'
> Q 'histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{destination_workload="notification-service-v1"}[1m])))'
> ```
>
> Expect something like:
>
> ```text
> {"status":"success",...,"result":[{"metric":{"response_code":"200"},"value":[...,"9.9"]}]}
> {"status":"success",...,"result":[{"metric":{},"value":[...,"0.9"]}]}
> {"status":"success",...,"result":[{"metric":{},"value":[...,"NaN"]}]}
> ```
>
> Ten requests a second, a p99 under a millisecond, and then the same percentile query with `by (le)` removed — which returns `NaN` or a nonsense figure rather than an error. That third line is the whole reason `le` gets its own warning: the query looks right, runs fine, and lies.
>
> The `Q` shell function is worth keeping for the rest of this module; every remaining checkpoint uses the same call.

## Where the reporter choice actually matters

For a healthy mesh either reporter gives the same answer and the choice is stylistic. It stops being stylistic in exactly the cases you are investigating:

- **Client-side faults** — an injected abort, a circuit breaker rejection, a client timeout — are recorded by `source` only. Query `destination` and the mesh looks healthy.
- **Server-side denials** — an `AuthorizationPolicy` `403` — are recorded by both, because the request arrived.
- **Requests that never arrive** — `NC`, `UH`, `UF` — appear in `source` with no `destination` counterpart.

The rule that falls out: **use `destination` for "is this service healthy", and `source` for "is this caller getting what it needs".** When they disagree, the disagreement is the finding, and [Part 3](./course-03-measuring-a-failure-and-grafana.md) produces one deliberately.

> [!WARNING]
> **Pitfalls with reporter and PromQL**
>
> - **Ignoring the `reporter` label.** Summing across both roughly doubles your rate, and the *difference* between them is often the actual finding.
> - **Dropping `le` when aggregating a histogram.** The query returns a number and it is meaningless. No error is raised.
> - **Mismatched filters in a ratio.** Numerator and denominator must be scoped identically apart from the selector under test.
> - **Reading a rate too soon after a change.** A `[1m]` window contains a minute of history. Wait out the window before trusting the value.
> - **Querying `destination` for a client-side fault.** Injected aborts, circuit breakers and timeouts never reach the destination's counters.
> - **Using a long window during an incident.** A `[5m]` rate smooths away exactly the transition you are trying to time.

> *Every request is counted twice on purpose — and when the two counts disagree, that disagreement is the diagnosis.*

## Reference

- [PromQL basics](https://prometheus.io/docs/prometheus/latest/querying/basics/) — selectors, ranges and the matching operators.
- [`histogram_quantile`](https://prometheus.io/docs/prometheus/latest/querying/functions/#histogram_quantile) — including the explicit requirement to keep the `le` label.
- [Istio standard metrics](https://istio.io/latest/docs/reference/config/metrics/) — the `reporter` label definition and the full label set.
- [Rate and irate](https://prometheus.io/docs/prometheus/latest/querying/functions/#rate) — what the window actually computes, and why counter resets are handled for you.
