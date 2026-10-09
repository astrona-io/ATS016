# Solution: Measure The Failure Before You Fix It

The cause is a `VirtualService` named `notification` that injects faults: it aborts about 30% of requests and delays half of them. You measure that with PromQL first, then remove it, declare access logging, and prove the fix with the same query.

Every query below uses Prometheus's HTTP interface from inside the cluster, so you need no browser. Define a helper first. `prom_query` sends its first argument to Prometheus from the `tester` pod:

```sh
prom_query() { kubectl -n metrics-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' --data-urlencode "query=$1"; echo; }
```

## Step 1: Generate load

Metrics are rates over a time window, so a handful of manual requests measures nothing. Start a background loop in the `tester` pod, about ten requests a second, and wait:

```sh
kubectl -n metrics-demo exec deploy/tester -- sh -c \
  'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.1; done" >/dev/null 2>&1 &'
sleep 90
```

The 90 seconds matter. A `[1m]` rate window that still holds samples from before the load gives a watered-down answer, and reading too early is the most common way to doubt a correct query.

## Step 2: Measure the error ratio

Divide the rate of `5xx` responses by the rate of all responses, from the client's side:

```sh
prom_query 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) / sum(rate(istio_requests_total{reporter="source"}[1m]))'
```

```text
{"metric":{},"value":[...,"0.29"]}
```

The answer is about `0.3`. `=~` is a regular-expression match, so `"5.."` is any three-character code starting with `5`. Dividing two sums gives a ratio that does not depend on traffic volume, which is what a service level objective is written against.

## Step 3: Find the asymmetry

Every request is counted twice: once by the client's proxy (`reporter="source"`) and once by the server's (`reporter="destination"`). Group the rate by both labels:

```sh
prom_query 'sum(rate(istio_requests_total{destination_workload="notification-service-v1"}[1m])) by (reporter, response_code)'
```

```text
{"reporter":"destination","response_code":"200"} 6.9
{"reporter":"source","response_code":"200"}      6.9
{"reporter":"source","response_code":"500"}      2.9
```

**The missing fourth series is the finding.** There is no `destination` line for `500`: the server never received those requests. The difference between the two views is a diagnosis in its own right:

| Pattern | Conclusion |
| --- | --- |
| errors in `source` only | the request never arrived — client-side configuration, connectivity, or the client's own limits |
| errors in both | it arrived and failed there — destination policy or the application |

The numbers confirm it: `6.9 + 2.9 ≈ 9.8`, the full rate. The failures were taken away from what reached the destination, not added to it. So the failure lives in the client's proxy, not in the service.

Name the cause with the response flag label, the short Envoy code the proxy writes next to each failed request. For an abort from fault injection the flag is `FI`, or `DI,FI` when the same request was also delayed:

```sh
prom_query 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) by (response_flags)'
```

## Step 4: See that latency lives in a different metric

A delayed request that succeeds is still a `200`, so the counters cannot see it. Ask the duration histogram for the 99th and 50th percentiles:

```sh
prom_query 'histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{destination_workload="notification-service-v1",reporter="source"}[1m])) by (le))'
prom_query 'histogram_quantile(0.50, sum(rate(istio_request_duration_milliseconds_bucket{destination_workload="notification-service-v1",reporter="source"}[1m])) by (le))'
```

```text
{"metric":{},"value":[...,"650"]}
{"metric":{},"value":[...,"480"]}
```

`le`, the bucket edge label, **must survive the aggregation**. Drop it and `histogram_quantile` returns an empty result with only a warning that the bucket label `le` is missing, and no error. Read these as "about half a second": a percentile is an estimate between bucket edges, not a measurement.

## Step 5: Find and remove the cause

Look for a fault in the namespace's `VirtualService` objects, delete the one that has it, wait for the window to slide past the fault, and measure again. Leave the load running, because a ratio needs traffic:

```sh
kubectl -n metrics-demo get virtualservice -o yaml | grep -A8 'fault:'
kubectl -n metrics-demo delete virtualservice notification
sleep 70
prom_query 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) / sum(rate(istio_requests_total{reporter="source"}[1m]))'
```

```text
{"metric":{},"value":[...,"0"]}
```

Counters keep their totals and **rates forget**. The ratio falls back to zero as the window slides past the fault; the old values are not erased. With no `VirtualService`, the proxies use Istio's default routing for the Service, which is a valid setup.

Send it for grading to see where you stand:

```sh
astrona submit
```

## Step 6: Declare access logging for the namespace

A `Telemetry` object configures metrics, access logs and tracing for the workloads in its namespace. With the `envoy` provider, every sidecar in `metrics-demo` writes one access log line per request.

Save this as `telemetry-access-logs.yaml`:

```yaml
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-logs
  namespace: metrics-demo
spec:
  accessLogging:
    - providers:
        - name: envoy
```

Apply it:

```sh
kubectl apply -f telemetry-access-logs.yaml
```

Metrics answer "how much, how bad, since when". Logs answer "what happened to *this* request". You want both, and the `Telemetry` object is the scoped way to ask for the second without touching the install. You undo it by deleting the object.

## Step 7: Stop the load and confirm

Stop the loop, send one request, and check that Grafana is running:

```sh
kubectl -n metrics-demo exec deploy/tester -- pkill -f 'while true' || true
kubectl -n metrics-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n istio-system get pods -l app.kubernetes.io/name=grafana
```

The request returns `200`, and the Grafana pod is `Running`.

## Step 8: Submit

The grader checks three things. The Prometheus and Grafana pods are `Running`. No `VirtualService` in `metrics-demo` has a `fault` block, and ten `POST` requests from `tester` all return `200`. A `Telemetry` object in `metrics-demo` enables the `envoy` provider, and Prometheus holds `istio_requests_total` with `response_code="200"` for `notification-service-v1`.

```sh
astrona submit
```

## Grafana

If your browser can reach the cluster, forward Grafana's port:

```sh
kubectl -n istio-system port-forward svc/grafana 3000:3000
```

Then open `http://localhost:3000` and pick the dashboard by the question:

| Dashboard | Open it for |
| --- | --- |
| **Istio Mesh** | the whole mesh — where to start when you do not know the service |
| **Istio Service** | client and server views side by side for one Service |
| **Istio Workload** | inbound **and outbound** traffic for one workload |
| **Istio Control Plane** | push errors, rejects, convergence time |

Every panel is a query you could have written. Open its Explore view to read the PromQL behind it.

## Common mistakes

- Forgetting `rate()` on a counter. A raw counter value means nothing for a rate question.
- Ignoring the `reporter` label and counting every request twice.
- Querying a window shorter than the scrape interval, which gives empty results.
- Dropping `by (le)` from a histogram query, which gives an empty result.
- Assuming missing metrics mean no traffic. A workload without a sidecar exports nothing at all.

## Practice variations

- Add a `Telemetry` resource with a custom dimension and query on it.
- Find requests rejected by a circuit breaker using the `response_flags` label.
- Use the Control Plane dashboard to connect a configuration push with a latency spike.
