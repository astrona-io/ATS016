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

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Envoy access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — turning logging on and reading the response flags
- [Common problems: network issues](https://istio.io/latest/docs/ops/common-problems/) — the catalogue of 503 causes and how to tell them apart
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
