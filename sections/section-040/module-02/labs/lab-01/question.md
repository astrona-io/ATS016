# Task: Trace A 503 To Its Exact Stage

**Time:** about 15 minutes · **Weight:** Troubleshooting the Mesh Data Plane

## Scenario

Every request to `notification-service` in `fivezerothree-demo` returns `503`.
The destination pod is `2/2 Running` with no restarts, and its application log
is empty:

```sh
kubectl -n fivezerothree-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n fivezerothree-demo get pods
```

## Your task

In the namespace `fivezerothree-demo`:

1. Establish **who** produced the `503` — the application or a proxy — from the
   access log's response flag. Record the flag before forming any theory.
2. Follow the route → cluster → endpoint chain on the client proxy to the exact
   link that is missing.
3. Repair it so traffic succeeds.

## Constraints

- **Do not invent a subset.** Adding a `DestinationRule` subset whose labels
  match no running pod would satisfy the analyzer and leave the traffic broken
  with a different flag. Any subset a route names must select at least one
  running pod.
- Do not delete the `DestinationRule`.
- Do not scale, restart or modify the Deployment, the Service or the `tester`
  pod. The workload is healthy.

## Done when

- Ten consecutive `POST` requests from `tester` all return `200`.
- Every cluster named by the proxy's route table exists in its cluster list.
- No `DestinationRule` subset exists whose labels select no running pod.
