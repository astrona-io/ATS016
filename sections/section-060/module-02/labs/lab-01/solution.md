# Solution: Measure The Failure Before You Fix It

Every query below uses the Prometheus HTTP API from inside the cluster, so no
browser is needed. Define a helper first:

```sh
Q() { kubectl -n metrics-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' --data-urlencode "query=$1"; echo; }
```

## Step 1 — Generate load

Metrics are rates over a window; a handful of manual requests measures nothing:

```sh
kubectl -n metrics-demo exec deploy/tester -- sh -c \
  'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.1; done" >/dev/null 2>&1 &'
sleep 90
```

Ninety seconds matters: a `[1m]` rate window still containing pre-load samples
reports something diluted, and reading too early is the commonest way to
disbelieve a correct query.

## Step 2 — Measure the error ratio

```sh
Q 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) / sum(rate(istio_requests_total{reporter="source"}[1m]))'
```

```text
{"metric":{},"value":[...,"0.29"]}
```

About `0.3`. `=~` is a regex match, so `"5.."` is any three-character code
starting with 5, and dividing two sums gives a ratio independent of traffic
volume — which is what an SLO is written against.

## Step 3 — Find the asymmetry

```sh
Q 'sum(rate(istio_requests_total{destination_workload="notification-service-v1"}[1m])) by (reporter, response_code)'
```

```text
{"reporter":"destination","response_code":"200"} 6.9
{"reporter":"source","response_code":"200"}      6.9
{"reporter":"source","response_code":"500"}      2.9
```

**The missing fourth series is the finding.** There is no `destination` line for
`500`: the server never received those requests. Every request is counted twice
— once by the client's proxy and once by the server's — and the difference
between the two is a diagnostic in its own right:

| Pattern | Conclusion |
| --- | --- |
| errors in `source` only | the request never arrived — client-side config, connectivity, or the client's own limits |
| errors in both | it arrived and failed there — destination policy or the application |

The arithmetic confirms it: `6.9 + 2.9 ≈ 9.8`, the full rate, with the failures
subtracted from what reached the destination rather than added to it.

Name the cause directly with the response-flag label:

```sh
Q 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) by (response_flags)'
```

## Step 4 — Latency lives in a different metric

A delayed success is still a `200`, so the counters cannot see it:

```sh
Q 'histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{destination_workload="notification-service-v1",reporter="source"}[1m])) by (le))'
Q 'histogram_quantile(0.50, sum(rate(istio_request_duration_milliseconds_bucket{destination_workload="notification-service-v1",reporter="source"}[1m])) by (le))'
```

```text
{"metric":{},"value":[...,"650"]}
{"metric":{},"value":[...,"480"]}
```

`le` — the bucket boundary label — **must survive the aggregation**. Drop it and
`histogram_quantile` returns `NaN` or a nonsense figure with no error raised.
Read these as "about half a second": a percentile is interpolated between bucket
boundaries, not measured.

## Step 5 — Find and remove the cause

```sh
kubectl -n metrics-demo get virtualservice -o yaml | grep -A8 'fault:'
kubectl -n metrics-demo delete virtualservice notification
sleep 70
Q 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) / sum(rate(istio_requests_total{reporter="source"}[1m]))'
```

```text
{"metric":{},"value":[...,"0"]}
```

Counters keep their totals and **rates forget** — the ratio falls back to zero
as the window slides past the fault, rather than the historical values being
erased. With no `VirtualService`, traffic falls back to Istio's default routing
for the Service, which is a perfectly valid configuration.

```sh
astrona submit
```

## Step 6 — Declare access logging for the namespace

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > telemetry-access-logs.yaml <<'EOF'
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-logs
  namespace: metrics-demo
spec:
  accessLogging:
    - providers:
        - name: envoy
EOF
kubectl apply -f telemetry-access-logs.yaml
```

Metrics answer "how much, how bad, since when". Logs answer "what happened to
*this* request". You want both, and the `Telemetry` object is the scoped,
revertible way to ask for the second.

## Step 7 — Stop the load and confirm

```sh
kubectl -n metrics-demo exec deploy/tester -- pkill -f 'while true' || true
kubectl -n metrics-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n istio-system get pods -l app.kubernetes.io/name=grafana
```

```sh
astrona submit
```

## Grafana

`kubectl -n istio-system port-forward svc/grafana 3000:3000`, then pick the
dashboard by the question:

| Dashboard | Open it for |
| --- | --- |
| **Istio Mesh** | the whole mesh — where to start when you do not know the service |
| **Istio Service** | client and server views side by side for one Service |
| **Istio Workload** | inbound **and outbound** traffic for one workload |
| **Istio Control Plane** | push errors, rejects, convergence time |

Every panel is a query you could have written — open its Explore view to read
the PromQL behind it.

## Common mistakes

- Forgetting `rate()` on a counter. Raw counter values are meaningless for a
  rate question.
- Ignoring the `reporter` label and double counting every request.
- Querying a window shorter than the scrape interval, which produces empty
  results.
- Assuming missing metrics mean no traffic. An uninjected workload exports
  nothing at all.
- Dropping `by (le)` from a histogram query.

## Practice variations

- Add a `Telemetry` resource with a custom dimension and query on it.
- Find requests rejected by a circuit breaker using the `response_flags` label.
- Use the Control Plane dashboard to correlate a config push with a latency
  spike.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Envoy access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — turning logging on and reading the response flags
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
