# Solution: Find Which Caller Is Failing With PromQL

Only `reports-client` gets errors. A `VirtualService` named `notification` has a rule that matches requests from `reports-client` and aborts 25% of them with a `503`, inside `reports-client`'s own sidecar proxy. You prove that with PromQL first, record it, then remove the fault and keep the route.

The output of these steps was not captured for this walkthrough, so each step says in words what the result shows instead of printing it. Work the task yourself first. Running `astrona submit` after a step tells you which checks pass.

Every query below uses Prometheus's HTTP interface from inside the cluster. Define a helper first. `prom_query` sends its first argument to Prometheus from the `tester` pod:

```sh
prom_query() { kubectl -n callers-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' --data-urlencode "query=$1"; echo; }
```

## Step 1: Find who is affected

Both clients already send requests in a loop, so you do not need to start any load. Group the client-side error rate by the calling workload:

```sh
prom_query 'sum(rate(istio_requests_total{destination_service_name="notification-service",reporter="source",response_code=~"5.."}[1m])) by (source_workload)'
```

The result has one series, with `"source_workload":"reports-client"`. There is no series for `orders-client`, because none of its requests failed. The `by (source_workload)` clause turns "the service fails now and then" into a list of affected callers, and the list has one name on it.

To see how large the problem is, divide the error rate by the total rate for each caller:

```sh
prom_query 'sum(rate(istio_requests_total{destination_service_name="notification-service",reporter="source",response_code=~"5.."}[1m])) by (source_workload) / sum(rate(istio_requests_total{destination_service_name="notification-service",reporter="source"}[1m])) by (source_workload)'
```

The ratio for `reports-client` is close to `0.25`. Both halves of the ratio use the same filters and the same reporter, and both are grouped by `source_workload`, so Prometheus divides each caller's errors by that same caller's total.

## Step 2: Find which side records the errors

Every request is counted twice: by the client proxy with `reporter="source"` and by the server proxy with `reporter="destination"`. Group the errors by reporter:

```sh
prom_query 'sum(rate(istio_requests_total{destination_service_name="notification-service",response_code=~"5.."}[1m])) by (reporter, source_workload)'
```

The only series is `reporter="source"` with `source_workload="reports-client"`. There is no `destination` series for these errors: `notification-service` never received the failed requests. So the failure happens in the client's sidecar proxy, not in the service both teams blame.

## Step 3: Name the response flag

Group the client-side errors by `response_flags`:

```sh
prom_query 'sum(rate(istio_requests_total{destination_service_name="notification-service",reporter="source",response_code=~"5.."}[1m])) by (response_flags)'
```

The flag is `FI`: fault injected. Envoy writes `FI` when a request is aborted by fault injection. That points straight at a `VirtualService` with a `fault` block.

## Step 4: Record the findings

Save this as `configmap-findings.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: findings
  namespace: callers-demo
data:
  failing-caller: reports-client
  reporter: source
  response-flag: FI
```

Apply it:

```sh
kubectl apply -f configmap-findings.yaml
```

Send it for grading to see where you stand:

```sh
astrona submit
```

The findings check passes. The fault check still fails, because the fault is still there.

## Step 5: Remove the fault, keep the route

Read the `VirtualService` to find the rule:

```sh
kubectl -n callers-demo get virtualservice notification -o yaml
```

The first `http` rule matches `sourceLabels: app: reports-client` and carries a `fault.abort` of `503` at 25%. The second rule is a plain route for every other caller. That is why only `reports-client` is affected. Replace the object with one plain route and no fault.

Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: callers-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

Then check the result. Send ten requests from `reports-client`, the caller that was failing:

```sh
kubectl -n callers-demo exec deploy/reports-client -- sh -c \
  'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -X POST http://notification-service/notify; done; echo'
```

All ten requests return `200`. If you wait a minute and run the ratio query from step 1 again, the value for `reports-client` falls to `0`: counters keep their totals, but the rate over the window forgets the old failures.

## Step 6: Submit

The grader checks three things. The Prometheus pod is `Running`. The ConfigMap `findings` holds `reports-client`, `source` and `FI`. The `VirtualService` `notification` still routes `notification-service` with no `fault` block, and ten requests from each client return `200`.

```sh
astrona submit
```

## Why the obvious shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Delete the `VirtualService` | traffic recovers, but the task requires the route to stay; the grader fails it |
| Guess the caller from the team that complained | the answer may be right, but it is not evidence; in a real incident, complaints and metrics often disagree |
| Query only `reporter="destination"` | the errors never reached the server, so the service looks healthy |
| Restart `notification-service` | nothing changes; the fault lives in the caller's proxy |

## Common mistakes

- Grouping by `destination_workload` instead of `source_workload`. Every request has the same destination here, so that grouping cannot tell the callers apart.
- Writing a ratio whose two halves are grouped differently. Group both halves by `source_workload`.
- Fixing before measuring. After the fix, a one-minute window soon holds no errors to measure.
