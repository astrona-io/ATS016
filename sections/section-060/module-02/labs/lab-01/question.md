# Question

Solve this question on: `terminal`

**Time:** about 25 minutes · **Exam topic:** Troubleshooting the Mesh Data Plane

## Scenario

`notification-service` in the namespace `metrics-demo` is failing some of the time. A colleague has already "checked with curl a few times" and reports that "it sometimes works". That is not a measurement.

Prometheus (the monitoring system that collects the proxies' metrics) and Grafana (the dashboard tool that draws them) are installed in `istio-system`. The namespace runs `notification-service-v1` behind the Service `notification-service` on port `80`, and a `tester` client pod with `curl`. Prometheus answers inside the cluster at `http://prometheus.istio-system:9090`.

## Your task

In the namespace `metrics-demo`:

1. Generate steady load and **measure** the failure with PromQL instead of by counting `curl` output: the error ratio, and which side of the connection records the errors.
2. Explain the difference you find between `reporter="source"` and `reporter="destination"`, and what it proves about where the failure lives.
3. Remove the cause, and prove with a query that the error ratio has returned to zero.
4. Declare access logging for the namespace with a `Telemetry` object that uses the `envoy` provider, so the next person has an access log line for each request as well as metrics.

## Constraints

- Do not modify the Deployments, the Service or the `tester` pod.
- Do not change the mesh-wide install configuration.
- Leave the namespace able to serve traffic. Removing the routing object entirely is acceptable only if requests still reach the Service.

## Done when

- The Prometheus and Grafana pods are `Running`.
- A `Telemetry` object in `metrics-demo` enables the `envoy` access log provider.
- No fault injection remains in any `VirtualService` in `metrics-demo`, and ten `POST` requests from `tester` all return `200`.
- Prometheus holds `istio_requests_total` series for `notification-service-v1` with `response_code="200"`.
