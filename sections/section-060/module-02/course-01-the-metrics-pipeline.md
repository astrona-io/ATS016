# Part 1 — The Metrics Pipeline

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — The reporter Label And PromQL Patterns](./course-02-reporter-and-promql.md).

Before querying anything it is worth knowing exactly where the numbers come from, because every gap in a dashboard is a break somewhere along a four-stage path. This part is that path, the metrics that travel it, and the two metric types you must read differently.

## Four stages, no application changes

```text
   ① the proxy counts        every request through the sidecar increments
      what it handles        istio_requests_total and observes the duration histogram

   ② it exposes them         :15090/stats/prometheus   (plain text, Prometheus format)

   ③ Prometheus scrapes      every ~15s, discovering pods by annotation or ServiceMonitor

   ④ something queries       Grafana, Kiali, or you — over Prometheus's HTTP API
```

The important property is where stage ① happens: **in the proxy**, not in your code. A workload gains full request metrics by gaining a sidecar, and loses them by losing one. No library, no instrumentation, no redeploy.

The consequences are the same ones [module 060-01](../../section-060/module-01/course-01-what-kiali-is-built-from.md) drew for Kiali, because Kiali is a consumer of this same pipeline:

- A workload with **no sidecar** produces nothing at any stage ([module 030-03](../../section-030/module-03/course.md)).
- Traffic that **bypasses the proxy** — an excluded port, a direct pod-IP call outside the mesh — is not counted.
- A **scrape gap** leaves a hole in the series that looks like an outage in a graph and is not one.

Diagnosing "no data" is a walk along those four stages, and stage ② is the one that splits the problem in half: if the proxy has the number and Prometheus does not, it is a monitoring problem, not a mesh one.

## The metrics that matter

| Metric | Type | Answers |
| --- | --- | --- |
| `istio_requests_total` | counter | How many requests, and how did they end? |
| `istio_request_duration_milliseconds_bucket` | histogram | How slow are they? |
| `istio_request_bytes` / `istio_response_bytes` | histogram | How large are the payloads? |
| `istio_tcp_connections_opened_total` / `_closed_total` | counter | Non-HTTP traffic, which the request metrics do not see |
| `istio_tcp_sent_bytes_total` / `received_bytes_total` | counter | Volume on TCP connections |

The TCP family matters more than it first appears. A database or a message broker in the mesh produces **no** `istio_requests_total` at all — those are HTTP-level metrics. Looking for a TCP service in the request metrics and concluding it has no traffic is a common and confident mistake.

## The labels are the tool

`istio_requests_total` carries the labels that make it a diagnostic rather than a number:

| Label | Values | Use |
| --- | --- | --- |
| `reporter` | `source`, `destination` | whose view of the request — [Part 2](./course-02-reporter-and-promql.md)'s subject |
| `source_workload`, `source_workload_namespace` | | who called |
| `destination_workload`, `destination_service_name` | | who was called |
| `destination_version` | the `version` pod label | canary comparison |
| `request_protocol` | `http`, `grpc`, `tcp` | protocol split |
| `response_code` | `200`, `503`, … | success and error rates |
| `response_flags` | `-`, `UH`, `UF`, `UO`, … | **the flag from [section 050](../../section-050/module-01/course-03-flags-and-which-proxy.md), as a label** |
| `connection_security_policy` | `mutual_tls`, `none` | encryption ([module 050-02](../../section-050/module-02/course-03-fixing-and-proving-encryption.md)) |

`response_flags` is the one people overlook, and it is the bridge between this section and section 050. A query grouped by it turns "we had 400 errors last night" into "380 of them were `UO`" — a capacity problem — "and 20 were `UF`" — a connectivity problem. That distinction would otherwise require reading hundreds of log lines.

## Reading one line

> [!TIP]
> **Try it — one metric line, read label by label**
>
> ```sh
> kubectl -n metrics-demo exec deploy/tester -- \
>   curl -s -o /dev/null -X POST http://notification-service/notify
> kubectl -n metrics-demo exec deploy/notification-service-v1 -c istio-proxy -- \
>   pilot-agent request GET stats/prometheus | grep '^istio_requests_total' | head -1
> ```
>
> Expect something like:
>
> ```text
> istio_requests_total{reporter="destination",source_workload="tester",source_workload_namespace="metrics-demo",destination_workload="notification-service-v1",destination_service_name="notification-service",request_protocol="http",response_code="200",response_flags="-",connection_security_policy="mutual_tls"} 1
> ```
>
> One line contains the caller, the callee, the protocol, the outcome, the response flag and whether the connection was encrypted. Everything Kiali draws and every Grafana panel is built from series like this one.
>
> `pilot-agent request GET` reads the sidecar's admin interface from inside the container ([module 010-02 Part 2](../../section-010/module-02/course-02-envoy-log-scopes-at-runtime.md)), which is **stage ②** of the pipeline. It works with or without Prometheus installed, which makes it the right first check when a dashboard is empty.

## Counters and histograms are read differently

**Counters** — `istio_requests_total`, the TCP totals — only ever increase, for the lifetime of the process. Three rules follow:

- **The absolute value means nothing.** `istio_requests_total ... 4213` is a statement about uptime.
- **The useful reading is a difference over time**, which is what `rate()` computes.
- **A pod restart resets them to zero.** Prometheus handles that in `rate()`; a human reading raw numbers must not be surprised by it.

**Histograms** are a set of `_bucket` series with an `le` ("less than or equal to") label, plus `_sum` and `_count`:

```text
   istio_request_duration_milliseconds_bucket{le="0.5"}   120
   istio_request_duration_milliseconds_bucket{le="1"}     180
   istio_request_duration_milliseconds_bucket{le="5"}     240
   istio_request_duration_milliseconds_bucket{le="+Inf"}  245
```

Each bucket is **cumulative**: `le="5"` counts every request that took 5ms *or less*. A percentile is computed by finding which bucket the target rank falls into and interpolating within it — which is why a percentile from a histogram is an estimate bounded by bucket width, not a measurement. "About 500ms" is the correct way to read one.

> [!TIP]
> **Try it — a histogram's buckets, raw**
>
> ```sh
> kubectl -n metrics-demo exec deploy/notification-service-v1 -c istio-proxy -- \
>   pilot-agent request GET stats/prometheus \
>   | grep '^istio_request_duration_milliseconds_bucket' | grep 'destination_workload="notification-service-v1"' | head -6
> ```
>
> Expect something like:
>
> ```text
> istio_request_duration_milliseconds_bucket{...,le="0.5"} 0
> istio_request_duration_milliseconds_bucket{...,le="1"} 1
> istio_request_duration_milliseconds_bucket{...,le="5"} 1
> istio_request_duration_milliseconds_bucket{...,le="10"} 1
> istio_request_duration_milliseconds_bucket{...,le="25"} 1
> istio_request_duration_milliseconds_bucket{...,le="50"} 1
> ```
>
> The counts stop changing after `le="1"` — every request so far completed in under a millisecond, so every larger bucket has the same cumulative count. Watch what [Part 3](./course-03-measuring-a-failure-and-grafana.md) does to this shape when it injects a 500ms delay: the low buckets stay put and the counts climb only from `le="500"` upwards.

## Querying Prometheus without a browser

Prometheus has an HTTP API, and any pod with `curl` can use it. That is what makes every checkpoint in this module work on a headless playground:

```sh
kubectl -n metrics-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' \
  --data-urlencode 'query=<PromQL>'
```

`--data-urlencode` matters: PromQL contains characters (`{`, `}`, `=`, `"`, `[`, `]`) that must be encoded, and building the URL by hand is how you get a confusing `400`.

The response is JSON with the shape `.data.result[]`, each element carrying a `metric` object of labels and a `value` pair of `[timestamp, "value"]`. Readable enough at a terminal; pipe to `jq` when there are more than a few series.

> [!WARNING]
> **Pitfalls in the pipeline**
>
> - **Expecting metrics from an unmeshed workload.** No sidecar, no `istio_requests_total`. A workload missing from a dashboard may be missing from the mesh.
> - **Looking for TCP traffic in the request metrics.** Non-HTTP connections appear in `istio_tcp_*`, not in `istio_requests_total`.
> - **Reading counters as absolute values.** A large number is uptime. Use `rate()`, or read twice and subtract.
> - **Treating a percentile as exact.** It is interpolated between bucket boundaries.
> - **Assuming the addon Prometheus is production monitoring.** The one shipped with Istio's samples has no persistent storage and is sized for demos.
> - **Building the query URL by hand.** Use `--data-urlencode`; PromQL is full of characters that need encoding.

> *A workload's metrics come from its proxy — so "no data" is first a question about the sidecar, and only then about monitoring.*

## Reference

- [Istio standard metrics](https://istio.io/latest/docs/reference/config/metrics/) — every metric and label this part names, authoritatively.
- [Prometheus metric types](https://prometheus.io/docs/concepts/metric_types/) — counters, gauges, histograms and summaries.
- [Querying Prometheus — HTTP API](https://prometheus.io/docs/prometheus/latest/querying/api/) — the endpoint and response shape used in every checkpoint here.
- [Istio Prometheus integration](https://istio.io/latest/docs/ops/integrations/prometheus/) — scrape configuration, and how to point Istio at an existing Prometheus rather than the addon.
