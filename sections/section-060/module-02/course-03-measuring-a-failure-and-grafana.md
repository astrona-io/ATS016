# Part 3 — Measuring A Known Failure, And Grafana

> Prerequisite: [Part 2 — The reporter Label And PromQL Patterns](./course-02-reporter-and-promql.md). Next: [the module landing page](./course.md).

A query you cannot check is a query you cannot trust. Fault injection gives a **known** answer — 30% errors, a 500ms delay — so the measurement can be verified against the thing being measured. This part does that, reads the client/server asymmetry it creates, and then maps the same data onto Grafana's bundled dashboards.

Keep the `Q` shell function from Part 2, and the load generator running.

```sh
Q() { kubectl -n metrics-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' --data-urlencode "query=$1"; echo; }
```

## Injecting a known failure

> [!TIP]
> **Try it — 30% errors and a 500ms delay on half the requests**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: notification
>   namespace: metrics-demo
> spec:
>   hosts:
>     - notification-service
>   http:
>     - fault:
>         abort:
>           httpStatus: 500
>           percentage:
>             value: 30
>         delay:
>           fixedDelay: 500ms
>           percentage:
>             value: 50
>       route:
>         - destination:
>             host: notification-service
> EOF
> sleep 90
> Q 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) / sum(rate(istio_requests_total{reporter="source"}[1m]))'
> ```
>
> Expect something like:
>
> ```text
> {"status":"success","data":{"resultType":"vector","result":[
>   {"metric":{},"value":[1774000000,"0.29"]}]}}
> ```
>
> Roughly `0.3` — the injected percentage, **measured** rather than assumed. Two details make this a real check rather than a coincidence. The `sleep 90` matters: a `[1m]` rate window still containing pre-fault samples reports something lower, and reading too early is the most common way to disbelieve a correct query. And `reporter="source"` matters more: the abort is injected by the *client's* proxy, so this ratio only exists on that side.

## The asymmetry, and what it proves

Run the same question without pinning the reporter and the two views separate.

> [!TIP]
> **Try it — the same fault, from both sides**
>
> ```sh
> Q 'sum(rate(istio_requests_total{destination_workload="notification-service-v1"}[1m])) by (reporter, response_code)'
> ```
>
> Expect something like:
>
> ```text
>   {"metric":{"reporter":"destination","response_code":"200"},"value":[...,"6.9"]},
>   {"metric":{"reporter":"source","response_code":"200"},"value":[...,"6.9"]},
>   {"metric":{"reporter":"source","response_code":"500"},"value":[...,"2.9"]}
> ```
>
> Three series, and **the missing fourth is the finding**: there is no `reporter="destination"` line for `500`. The server never received those requests, because the client's own proxy aborted them.
>
> Read the rates too — `6.9` successful on both sides, `2.9` failed on the client only, totalling the ~9.8 requests/second from Part 2. The arithmetic confirms that the `500`s were subtracted from what reached the destination rather than added to it.

In a real incident this asymmetry is the evidence that the failure lives in the client's proxy or the network between them, **not** in the service everyone is blaming. Stated as a rule:

| Pattern | Conclusion |
| --- | --- |
| errors in `source` only | the request never arrived — client-side config, connectivity, or the client's own limits |
| errors in both | it arrived and failed there — destination policy or the application |
| errors in `destination` only | rare; the response path, or a caller outside the mesh you are not seeing |

Adding `by (response_flags)` to the same query names the client-side cause outright, in section 050's vocabulary:

```sh
Q 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) by (response_flags)'
```

## Latency lives in a different metric

The delay half of the fault does not appear in the counters at all — a delayed request that succeeds is still a `200`. It appears in the duration histogram, which is why "is it slow or is it failing" is two queries rather than one.

> [!TIP]
> **Try it — the p99, against a known injected delay**
>
> ```sh
> Q 'histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{destination_workload="notification-service-v1",reporter="source"}[1m])) by (le))'
> Q 'histogram_quantile(0.50, sum(rate(istio_request_duration_milliseconds_bucket{destination_workload="notification-service-v1",reporter="source"}[1m])) by (le))'
> ```
>
> Expect something like:
>
> ```text
>   {"metric":{},"value":[1774000000,"650"]}
>   {"metric":{},"value":[1774000000,"480"]}
> ```
>
> Several hundred milliseconds against an application that answers in under one — the injected 500ms, visible in the tail. The median is the more interesting number here: with the delay applied to **50%** of requests, the p50 sits right at the boundary between delayed and undelayed traffic, which is exactly what a half-and-half distribution should produce.
>
> Neither figure is exact. A percentile is interpolated between bucket boundaries ([Part 1](./course-01-the-metrics-pipeline.md)), so read these as "about half a second" rather than as measurements. Comparing p50 against p99 is the practical technique: close together means uniformly slow, far apart means a slow tail affecting some requests.

## Grafana

Grafana's bundled Istio dashboards are these same queries, pre-written and arranged. Four ship with the addon, and knowing which to open is most of the value:

| Dashboard | Scope | Open it for |
| --- | --- | --- |
| **Istio Mesh** | everything | the whole mesh at a glance: rate, success rate and latency per service. Where to start when you do not know which service is involved. |
| **Istio Service** | one Service | client and server views side by side, broken down by source workload — the `reporter` comparison above, as panels. |
| **Istio Workload** | one workload | inbound **and outbound** traffic, so you can see what it calls as well as who calls it. |
| **Istio Control Plane** | `istiod` | push errors, rejected configuration, convergence time, memory — the dashboard for [module 030-01's](../../section-030/module-01/course-02-instruments-logs-and-metrics.md) symptoms. |

The Workload dashboard's outbound half is the one people forget. When a service is slow, its *outbound* panels answer "is it slow because something it calls is slow" without opening a second dashboard.

Reach it the same way as any other addon UI:

```sh
kubectl -n istio-system port-forward svc/grafana 3000:3000
```

Then open `http://localhost:3000` from a browser that can reach this machine. `istioctl dashboard grafana` does the same and additionally tries to launch a browser.

One habit is worth more than any individual dashboard: when a panel shows something surprising, open its **Explore** view to see the PromQL behind it. Every panel is a query you could have written, and reading them is the fastest way to learn the ones you did not know about — including several `by (...)` groupings that are not obvious from the documentation.

## Cleaning up

> [!TIP]
> **Try it — removing the fault and stopping the load**
>
> ```sh
> kubectl -n metrics-demo exec deploy/tester -- pkill -f 'while true' || true
> kubectl -n metrics-demo delete virtualservice notification
> sleep 5
> kubectl -n metrics-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
> ```
>
> Expect something like:
>
> ```text
> virtualservice.networking.istio.io "notification" deleted
> 200
> ```
>
> Traffic is healthy again. The error ratio in Prometheus falls back toward zero over the following minute as the rate window slides past the fault — **counters keep their totals, and rates forget.** That sentence is the whole difference between reading a raw metric and reading a query over it, and it is worth carrying out of this section.

## The questions metrics answer

| Question | Query shape |
| --- | --- |
| Is it broken, or was that one bad request? | error ratio |
| When did it start? | the same ratio, as a graph over a range |
| Who is affected? | `by (source_workload)` |
| Why is it failing? | `by (response_flags)` |
| Is it slow, or failing? | duration histogram against the code counter |
| Is the canary worse? | `by (destination_version)` |
| Is it encrypted? | `by (connection_security_policy)` |
| Which side sees the failure? | `by (reporter)` |

Every one of those is the same `sum(rate(...)) by (...)` with a different grouping. That is the practical takeaway: learn one query shape and a list of labels, not a list of queries.

> [!WARNING]
> **Pitfalls in measuring**
>
> - **Reading a rate before the window has cleared.** A `[1m]` window still containing pre-change samples gives a diluted answer. Wait a full window.
> - **Querying the wrong reporter for a client-side fault.** Injected aborts, circuit breakers and timeouts never reach the destination's counters.
> - **Looking for latency in the code counters.** A delayed success is still a `200`; the histogram is the only place it shows.
> - **Treating a percentile as exact.** It is interpolated; compare p50 against p99 rather than trusting a single figure.
> - **Forgetting to remove fault injection.** It keeps working after you stop looking at the graph.
> - **Assuming the addon stack is production monitoring.** The sample Prometheus has no persistent storage; the history you are relying on may not survive its pod.

> *Counters keep their totals and rates forget — which is why every question in this section is a query over time, not a number.*

## Reference

- [Fault injection](https://istio.io/latest/docs/tasks/traffic-management/fault-injection/) — `abort` and `delay`, and which proxy applies each.
- [Istio Grafana dashboards](https://istio.io/latest/docs/ops/integrations/grafana/) — the four dashboards, and importing them into an existing Grafana.
- [`histogram_quantile`](https://prometheus.io/docs/prometheus/latest/querying/functions/#histogram_quantile) — interpolation, and the `le` requirement.
- [Istio standard metrics](https://istio.io/latest/docs/reference/config/metrics/) — the label list behind the question table above.
