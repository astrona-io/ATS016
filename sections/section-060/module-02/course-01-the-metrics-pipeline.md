# The Metrics Pipeline

Before you query anything, learn exactly where the numbers come from. Every gap in a dashboard is a break somewhere along one four-step path, from the sidecar proxy to Prometheus to the tool you read. This part covers that path, the metrics that travel along it, and the two kinds of metric you must read differently.

## Four steps, no application changes

Each request passes a sidecar proxy, and the proxy keeps count. Prometheus collects those counts, and other tools read them from Prometheus.

```mermaid
flowchart LR
    P["Sidecar proxy"] -->|"exposes :15090/stats/prometheus"| E["Metrics page"]
    E -->|"scraped every ~15s"| PR["Prometheus"]
    PR -->|"HTTP queries"| Q["Grafana, Kiali or you"]
```

The diagram shows the four steps: the proxy counts, exposes, Prometheus scrapes, and a tool queries.

First, the proxy adds one to `istio_requests_total` for every request it handles, and records how long the request took. Second, it shows those numbers as plain text on port `15090`, in the Prometheus text format. Third, Prometheus collects them about every 15 seconds; this is called scraping. Fourth, Grafana, Kiali or you read them through Prometheus's HTTP interface.

The key fact is where the first step happens: **in the proxy**, not in your code. A workload gets full request metrics by getting a sidecar, and loses them by losing it. It needs no library, no code change and no redeploy. Three things follow from that. A workload with **no sidecar** produces nothing at any step. Traffic that **goes around the proxy**, such as an excluded port or a direct call from outside the mesh, is not counted. And a **missed scrape** leaves a hole in the data that looks like an outage on a graph, and is not one.

To explain "no data", walk along the four steps. The second step splits the problem in half: if the proxy has the number and Prometheus does not, it is a monitoring problem, not a mesh problem.

## The metrics that matter

Istio's sidecar proxies export a small set of standard metrics. These are the ones you use for troubleshooting:

| Metric | Type | Answers |
| --- | --- | --- |
| `istio_requests_total` | counter | How many requests, and how did they end? |
| `istio_request_duration_milliseconds_bucket` | histogram | How slow are they? |
| `istio_request_bytes` / `istio_response_bytes` | histogram | How large are the bodies? |
| `istio_tcp_connections_opened_total` / `_closed_total` | counter | Traffic that is not HTTP, which the request metrics do not see |
| `istio_tcp_sent_bytes_total` / `istio_tcp_received_bytes_total` | counter | Volume on TCP connections |

The TCP metrics matter more than they first seem. A database or a message broker in the mesh produces **no** `istio_requests_total` at all, because those are HTTP-level metrics. Looking for a TCP service in the request metrics and deciding it has no traffic is a common, confident mistake.

## The labels are the tool

A metric on its own is just a number. The labels on `istio_requests_total` are what turn that number into a diagnosis:

| Label | Values | Use |
| --- | --- | --- |
| `reporter` | `source`, `destination` | whose view of the request: the client proxy's or the server proxy's |
| `source_workload`, `source_workload_namespace` | | who called |
| `destination_workload`, `destination_service_name` | | who was called |
| `destination_version` | the `version` pod label | canary comparison |
| `request_protocol` | `http`, `grpc`, `tcp` | protocol split |
| `response_code` | `200`, `503`, … | success and error rates |
| `response_flags` | `-`, `UH`, `UF`, `UO`, … | **the response flag from the access log, as a label** |
| `connection_security_policy` | `mutual_tls`, `none`, `unknown` | whether the connection used mutual TLS (mTLS); filled in on the destination, `unknown` on the source |

`response_flags` is the label people overlook, and it links metrics to access logs. A response flag is the short Envoy code that the sidecar proxy writes in the access log to say why a request failed. A query grouped by it turns "we had 400 errors last night" into "380 were `UO`", which is a capacity problem where a circuit breaker rejected requests, "and 20 were `UF`", which is a connection problem. Without it you would read hundreds of log lines to learn the same thing.

The fastest way to understand the labels is to read one real line from a proxy. Send one request from the `tester` pod, then read the first `istio_requests_total` line from the destination's sidecar proxy:

<!-- astrona:playground:renew -->

```sh
kubectl -n metrics-demo exec deploy/tester -- \
  curl -s -o /dev/null -X POST http://notification-service/notify
kubectl -n metrics-demo exec deploy/notification-service-v1 -c istio-proxy -- \
  pilot-agent request GET stats/prometheus | grep '^istio_requests_total' | head -1
```

You should see something like:

```text
istio_requests_total{reporter="destination",source_workload="tester",source_canonical_service="tester",source_canonical_revision="latest",source_workload_namespace="metrics-demo",source_principal="spiffe://cluster.local/ns/metrics-demo/sa/default",source_app="tester",source_version="unknown",source_cluster="Kubernetes",destination_workload="notification-service-v1",destination_workload_namespace="metrics-demo",destination_principal="spiffe://cluster.local/ns/metrics-demo/sa/default",destination_app="notification-service",destination_version="v1",destination_service="notification-service.metrics-demo.svc.cluster.local",destination_canonical_service="notification-service",destination_canonical_revision="v1",destination_service_name="notification-service",destination_service_namespace="metrics-demo",destination_cluster="Kubernetes",request_protocol="http",response_code="200",grpc_response_status="",response_flags="-",connection_security_policy="mutual_tls"} 1
```

The real line is long, because Istio adds a label for every part of both identities, such as `source_principal` and `destination_canonical_service`. Find the labels from the table in it: one line holds the caller, the callee, the protocol, the result, the response flag and whether the connection was encrypted. Every edge Kiali draws and every Grafana panel is built from lines like this one.

`pilot-agent request GET` reads the sidecar proxy's administration page from inside the `istio-proxy` container. That is the second step of the path. It works with or without Prometheus, which makes it the right first check when a dashboard is empty.

## Counters and histograms are read differently

Istio's metrics come in two kinds, and you read each kind in its own way. Get this wrong and every number you read is wrong too.

### Counters only go up

**Counters**, such as `istio_requests_total` and the TCP totals, only ever go up for as long as the proxy runs. So the raw value means nothing: `istio_requests_total ... 4213` only tells you how long the proxy has been up. The useful reading is the change over time, which is what the PromQL function `rate()` calculates. A pod restart resets counters to zero. Prometheus handles that inside `rate()`, but a person reading raw numbers must not be surprised by it.

### Histograms count into buckets

**Histograms** are a set of `_bucket` series with an `le` label ("less than or equal to"), plus a `_sum` and a `_count`:

```text
   istio_request_duration_milliseconds_bucket{le="0.5"}   120
   istio_request_duration_milliseconds_bucket{le="1"}     180
   istio_request_duration_milliseconds_bucket{le="5"}     240
   istio_request_duration_milliseconds_bucket{le="+Inf"}  245
```

Each bucket is **cumulative**: `le="5"` counts every request that took 5 milliseconds *or less*. To get a percentile, Prometheus finds the bucket the target rank falls into and estimates a value inside it. So a percentile from a histogram is an estimate, limited by the bucket size, and "about 500ms" is the right way to read one.

To see real buckets, read the first six duration buckets for the application from its own sidecar proxy:

```sh
kubectl -n metrics-demo exec deploy/notification-service-v1 -c istio-proxy -- \
  pilot-agent request GET stats/prometheus \
  | grep '^istio_request_duration_milliseconds_bucket' | grep 'destination_workload="notification-service-v1"' | head -6
```

You should see something like:

```text
istio_request_duration_milliseconds_bucket{...,le="0.5"} 0
istio_request_duration_milliseconds_bucket{...,le="1"} 0
istio_request_duration_milliseconds_bucket{...,le="5"} 0
istio_request_duration_milliseconds_bucket{...,le="10"} 0
istio_request_duration_milliseconds_bucket{...,le="25"} 0
istio_request_duration_milliseconds_bucket{...,le="50"} 0
```

The labels are shortened to `...` here. Each line is one bucket of one series, and the proxy keeps one series for every combination of labels, so the series you see first can differ. In this run all six counts are `0`: no request in this series finished within 50 milliseconds, so every one sits in a larger bucket. In another series the count may jump at a low bucket such as `le="1"` and then stay the same. Either way, a count that stays the same from one bucket to the next means no request finished between those two edges. If you add a 500ms delay to some requests, the low buckets stay where they are and the counts only climb from `le="500"` upwards.

## Querying Prometheus without a browser

Reading a proxy directly shows one pod's numbers. For numbers across the mesh and over time, you ask Prometheus. Prometheus has an HTTP interface, and any pod with `curl` can use it, which is why every hands-on step in this module works with no browser. This is the general shape of the command; you replace `<PromQL>` with a real query:

```sh
kubectl -n metrics-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' \
  --data-urlencode 'query=<PromQL>'
```

The `--data-urlencode` flag matters. PromQL contains characters (`{`, `}`, `=`, `"`, `[`, `]`) that must be encoded, and building the address by hand is how you get a confusing `400` error. The answer is JSON shaped like `.data.result[]`. Each item has a `metric` object with the labels and a `value` pair of `[timestamp, "value"]`. That is readable in a terminal; pipe it to `jq` when there are more than a few series.

You now know where every number starts: in the sidecar proxy, which counts each request, exposes it on port `15090`, and lets Prometheus scrape it. You know which metric answers which question, that the labels carry the diagnosis, and that counters need `rate()` while histograms give estimates. The open question is the `reporter` label, because every request you just counted was counted twice.

## Common pitfalls

> [!WARNING]
> - **Expecting metrics from a workload outside the mesh.** No sidecar, no `istio_requests_total`. A workload missing from a dashboard may be missing from the mesh.
> - **Looking for TCP traffic in the request metrics.** Connections that are not HTTP appear in `istio_tcp_*`, not in `istio_requests_total`.
> - **Reading counters as absolute values.** A large number only means a long uptime. Use `rate()`, or read twice and subtract.
> - **Treating a percentile as exact.** It is an estimate between bucket edges.
> - **Taking the add-on Prometheus for production monitoring.** The one in Istio's samples has no permanent storage and is sized for demos.
> - **Building the query address by hand.** Use `--data-urlencode`; PromQL is full of characters that need encoding.
