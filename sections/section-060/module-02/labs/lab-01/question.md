# Task: Measure The Failure Before You Fix It

**Time:** about 25 minutes · **Weight:** Troubleshooting the Mesh Data Plane

## Scenario

`notification-service` in `metrics-demo` is failing intermittently. A colleague
has already "checked with curl a few times" and reports that "it sometimes
works". That is not a measurement.

Prometheus and Grafana are installed.

## Your task

In the namespace `metrics-demo`:

1. Generate steady load and **measure** the failure with PromQL rather than by
   counting `curl` output: the error ratio, and which side of the connection
   records the errors.
2. Explain the asymmetry you find between `reporter="source"` and
   `reporter="destination"`, and what it proves about where the failure lives.
3. Remove the cause, and prove with a query that the error ratio has returned
   to zero.
4. Declare access logging for the namespace with a `Telemetry` object, so the
   next person has per-request evidence as well as metrics.

## Constraints

- Do not modify the Deployments, the Service or the `tester` pod.
- Do not change the mesh-wide install configuration.
- Leave the namespace able to serve traffic — removing the routing object
  entirely is acceptable only if requests still reach the Service.

## Done when

- Prometheus and Grafana pods are `Running`.
- A `Telemetry` object in `metrics-demo` enables the `envoy` access log
  provider.
- No fault injection remains, and a `POST` from `tester` returns `200`.
- Prometheus holds `istio_requests_total` series for the workload with
  `response_code="200"`.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Envoy access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — turning logging on and reading the response flags
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
