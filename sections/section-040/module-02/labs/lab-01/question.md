# Question

Solve this question on: `terminal`

**Time:** about 15 minutes · **Weight:** Troubleshooting the Mesh Data Plane

## Scenario

Every request to `notification-service` in the namespace `fivezerothree-demo` returns `503`. The destination pod is `2/2 Running` with no restarts, and its app log is empty:

```sh
kubectl -n fivezerothree-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n fivezerothree-demo get pods
```

## Your task

In the namespace `fivezerothree-demo`:

1. Find out **who** produced the `503`, the app or a proxy, from the access log's response flag. Write the flag down before you form any theory.
2. Follow the route, cluster and endpoint chain on the client proxy (`tester`) to the exact link that is missing.
3. Repair it so traffic succeeds.

## Constraints

- **Do not invent a subset.** Adding a `DestinationRule` subset whose labels match no running pod would satisfy the analyzer and leave the traffic broken with a different flag. Any subset a route names must select at least one running pod.
- Do not delete the `DestinationRule` named `notification`.
- Do not scale, restart or change the Deployment, the Service or the `tester` pod. The workload is healthy.

## Done when

- Ten `POST` requests in a row from `tester` to `http://notification-service/notify` all return `200`.
- Every cluster for `notification-service` that the `tester` proxy's route table names exists in its cluster list.
- The `DestinationRule` `notification` still exists, and no `DestinationRule` subset has labels that select no running pod.
