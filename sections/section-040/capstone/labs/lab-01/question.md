# Question

Solve this question on: `terminal`

**Time:** about 35 minutes · **Weight:** Troubleshooting the Mesh Data Plane

## Scenario

Astronaut, the planet (namespace) `dpcapstone-demo` runs two services, and neither behaves. Both destination pods are `2/2 Running` with no restarts.

```sh
kubectl -n dpcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'notification %{http_code}\n' -X POST http://notification-service/notify
kubectl -n dpcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'reporting    %{http_code}\n' http://reporting-service/status
```

A `VirtualService` exists for each of them. The team has rewritten both several times and nothing changes. In particular, the `reporting-service` routing rule "is simply ignored".

## Your task

1. For **each** service, find which of Envoy's four stages (listener, route, cluster, endpoint) the request fails at. Use the access log's response flag and `istioctl proxy-config`; do not guess from the YAML.
2. Fix both. The two causes are different, and so are the two fixes.
3. Be able to explain why one of the two failures made a whole `VirtualService` do nothing, rather than producing a routing error.

## Constraints

- **Do not invent a subset.** Any subset a route names must select at least one running pod.
- Do not change the Deployments' container specs or the `tester` pod.
- `reporting-service` must stay reachable on port 80 with the same target port (8080). Fix how the port is *declared*, not which port it is.

## Done when

- Both services return `200` from the `tester` pod (`POST /notify` to `notification-service`, `GET /status` to `reporting-service`).
- Every cluster for the two services that the `tester` proxy's route table names exists, with at least one `HEALTHY` endpoint.
- The `reporting-service` port declares an HTTP protocol (by its name, such as `http`, or by `appProtocol`) and still maps 80 to 8080.
- The `tester` proxy holds an HTTP route for `reporting-service`, and its port-80 listener hands off to a `Route:`.
