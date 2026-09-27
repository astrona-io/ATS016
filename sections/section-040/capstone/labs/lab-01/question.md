# Capstone: Two 503s, Two Different Stages

**Time:** about 35 minutes · **Weight:** Troubleshooting the Mesh Data Plane
**Covers:** modules 1–2 (reading proxy configuration, diagnosing a 503)

## Scenario

`dpcapstone-demo` runs two services and neither behaves. Both destination pods
are `2/2 Running` with no restarts.

```sh
kubectl -n dpcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'notification %{http_code}\n' -X POST http://notification-service/notify
kubectl -n dpcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'reporting    %{http_code}\n' http://reporting-service/status
```

A `VirtualService` exists for each of them. The team has rewritten both several
times and nothing changes — in particular, the `reporting-service` routing rule
"is simply ignored".

## Your task

1. For **each** service, identify which of Envoy's four stages — listener,
   route, cluster, endpoint — the request fails at. Use the access log's
   response flag and `istioctl proxy-config`; do not guess from the YAML.
2. Fix both. The two causes are different and so are the two fixes.
3. Be able to explain why one of the two failures made an entire
   `VirtualService` inert rather than producing a routing error.

## Constraints

- **Do not invent a subset.** Any subset a route names must select at least one
  running pod.
- Do not modify the Deployments' container specs or the `tester` pod.
- `reporting-service` must remain reachable on port 80 with the same target
  port — fix how the port is *declared*, not which port it is.

## Done when

- Both services return `200` from the `tester` pod.
- Every cluster named by the proxy's route table exists with healthy endpoints.
- The `reporting-service` port declares an HTTP protocol, and the `tester` proxy
  holds an HTTP route for it.
