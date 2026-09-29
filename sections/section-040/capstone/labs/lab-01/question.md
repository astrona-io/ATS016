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

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Describing pod configuration](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-describe/) — what the mesh is applying to one workload
- [Envoy access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — turning logging on and reading the response flags
- [Common problems: network issues](https://istio.io/latest/docs/ops/common-problems/) — the catalogue of 503 causes and how to tell them apart
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
