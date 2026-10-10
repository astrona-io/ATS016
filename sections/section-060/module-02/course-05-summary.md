# Summary

Logs and proxy configuration explain one request on one proxy. This module showed how Istio's metrics answer the questions they cannot: how many requests fail, how slow they are, since when, for which caller, and on which side of the connection.

## What you learned

Every request metric starts in the sidecar proxy. The proxy counts each request in `istio_requests_total` and records its duration in `istio_request_duration_milliseconds_bucket`, exposes them on port `15090`, and Prometheus scrapes them about every 15 seconds. A workload with no sidecar produces no metrics, and traffic that is not HTTP appears only in the `istio_tcp_*` metrics. When a dashboard is empty, read the proxy's own metrics with `pilot-agent request GET stats/prometheus` before you blame the monitoring.

Counters only go up, so their raw value means nothing, and `rate()` turns them into a per-second change. Histograms count requests into cumulative buckets with an `le` label, and a percentile from them is an estimate between bucket edges. The labels carry the diagnosis: `source_workload` names who is affected, `response_flags` names why requests fail, and `connection_security_policy` shows mTLS on the destination.

Every request is counted twice, once with `reporter="source"` by the client proxy and once with `reporter="destination"` by the server proxy. Adding both together doubles the rate. The difference between them is a finding: errors seen only by the source never reached the server, as with an injected abort, which Envoy marks with the response flag `FI`. Three query shapes cover most troubleshooting: a rate grouped by a label, a ratio of two rates with matching filters and reporter, and `histogram_quantile` over rates that keep `le`. A fault with a known answer is the honest way to check a query.

Grafana's bundled Istio dashboards are the same queries, already drawn: Istio Mesh to start, Istio Service for the two views of one Service, Istio Workload for inbound and outbound traffic, and Istio Control Plane for `istiod`. A `Telemetry` object with the `envoy` provider turns on access logs for one namespace only. The key facts to remember are these:

- Use `destination` for "is this service healthy" and `source` for "is this caller getting what it needs".
- A delayed request that succeeds is still a `200`; only the duration histogram shows it.
- Without `le` in the `by` clause, `histogram_quantile` returns an empty result and only a warning.
- Counters keep their totals and rates forget, so prove a fix with the same query after a full window.

<!-- astrona:playground:destroy -->
