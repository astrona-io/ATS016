# Question

Solve this question on: `terminal`

**Time:** about 20 minutes · **Exam topic:** Troubleshooting the Mesh Data Plane

## Scenario

Callers of `notification-service` in the namespace `accesslog-demo` report that their requests "hang for several seconds and then come back". A dependency is slow, and the team wants callers to fail fast instead of waiting:

```sh
time kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

The cluster also has access logging switched on for the whole mesh: every sidecar proxy writes one line per request to its access log. The platform team wants to reduce that: they would like this namespace's logging declared explicitly, as an object in the namespace, instead of inherited from the install.

## Your task

In the namespace `accesslog-demo`:

1. Create a `Telemetry` object that switches on the built-in Envoy access log provider (`envoy`) **for this namespace**.
2. Bound the slow dependency with a **2 second** request timeout on the `VirtualService` for `notification-service`, so a caller gives up instead of waiting five seconds.
3. Send a request and find the response flag the timeout produces in the access log. Be able to say which proxy wrote that line.

## Constraints

- **Do not touch the dependency.** `notification-service` really is slow to answer. Bound the wait from the caller's side; do not make the dependency faster.
- The timeout must be on the `VirtualService` route, not a `curl` option.
- Do not change the mesh-wide install configuration.

## Done when

- A `Telemetry` object in `accesslog-demo` switches on the `envoy` access log provider.
- The `VirtualService` for `notification-service` sets `timeout: 2s`.
- The `tester` proxy's access log contains a `UT` response flag.
