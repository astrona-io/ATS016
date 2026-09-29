# Task: Scope The Logs, Bound The Latency, Name The Flag

**Time:** about 20 minutes · **Weight:** Troubleshooting the Mesh Data Plane

## Scenario

Callers of `notification-service` in `accesslog-demo` report that requests
"hang for about five seconds and then come back". A dependency is slow, and the
team wants callers to fail fast rather than wait:

```sh
time kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

The cluster also has access logging enabled mesh-wide, which the platform team
wants reduced — they would like this namespace's logging declared explicitly as
a namespaced object rather than inherited from the install.

## Your task

In the namespace `accesslog-demo`:

1. Create a `Telemetry` object that enables the built-in Envoy access log
   provider **for this namespace**.
2. Bound the slow dependency with a **2 second** request timeout, so a caller
   gives up rather than waiting five.
3. Send a request and identify the response flag the timeout produces. Be able
   to say which proxy wrote the line and why the destination's log is silent.

## Constraints

- **Do not touch the dependency.** `notification-service` really does take about
  five seconds to answer; the task is to bound the wait from the caller's side,
  not to make the dependency faster.
- The timeout must be on the `VirtualService` route, not a client-side `curl`
  option.
- Do not change the mesh-wide install configuration.

## Done when

- A `Telemetry` object in `accesslog-demo` enables the `envoy` access log
  provider.
- The `VirtualService` for `notification-service` sets `timeout: 2s`.
- The `tester` proxy's access log contains a `UT` response flag.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Envoy access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — turning logging on and reading the response flags
- [Common problems: network issues](https://istio.io/latest/docs/ops/common-problems/) — the catalogue of 503 causes and how to tell them apart
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
