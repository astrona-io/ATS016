# Question

Solve this question on: `terminal`

**Time:** about 25 minutes · **Exam topic:** Troubleshooting the Mesh Data Plane

## Scenario

In the namespace `accesslog-demo`, the `tester` pod calls `notification-service`. The team's intent is simple: `notification-service` refuses `DELETE` requests and accepts everything else, and its callers may send bursts of requests at the same time.

Two different failures are reported. A single `POST` returns `403`, and when many `POST` requests are sent at the same time, some of them return `503` as well:

```sh
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

Both pods are `2/2 Running`, and access logging is on for the whole mesh.

## Your task

In the namespace `accesslog-demo`:

1. Find the cause of the `403` from the access logs. Say which proxy decided it, and name the object that refused the request.
2. Find the cause of the `503` from the access logs. Say which proxy decided it, and name its response flag.
3. Fix both faults so that the intent holds.

## Constraints

- Do not delete the `AuthorizationPolicy` `block-delete`, and keep it a `DENY` policy. It must still refuse `DELETE`.
- Do not delete the `DestinationRule` `notification`, and keep a `connectionPool.tcp.maxConnections` limit in it. Raise the limits instead of removing them.
- Do not change the Deployments, the Service or the `tester` pod.

## Done when

- Ten `POST` requests in a row from `tester` to `http://notification-service/notify` all return `200`.
- A `DELETE` from `tester` to the same address returns `403`, and `block-delete` is still a `DENY` policy.
- Twenty `POST` requests sent at the same time from `tester` all return `200`, and the `DestinationRule` `notification` still sets `connectionPool.tcp.maxConnections`.
