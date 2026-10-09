# Solution: Measure A Failure, Fix It, Prove It

The graph is empty because no traffic flows. Once traffic flows, about 40% of requests fail, and three configuration faults sit behind it: a fault drill, a route to a subset nobody built, and two flight plans for one beacon. You measure first, fix all three with one consolidation, declare access logging, and prove the fix with the same query.

Every measurement below uses Prometheus's HTTP interface from inside the cluster, so you need no browser. Define the query helper first. `prom_query` sends its first argument to Prometheus from the `tester` pod:

```sh
prom_query() { kubectl -n obscapstone-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' --data-urlencode "query=$1"; echo; }
```

## Step 1: Show the empty graph is not an outage

Check all three add-ons:

```sh
kubectl -n istio-system get pods -l app=kiali
kubectl -n istio-system get pods -l app.kubernetes.io/name=prometheus
kubectl -n istio-system get pods -l app.kubernetes.io/name=grafana
```

All are `Running`. Kiali stores nothing: it reads Istio objects from the API server and metrics from Prometheus. So an empty graph means one of two things: Prometheus is missing, or there is no traffic. "The mesh is down" is neither of them.

The graph is built from `istio_requests_total` over a time window. **No requests in the window means no edges, and a node with no edges is not drawn.** An idle service is invisible. Start a background load loop in the `tester` pod, about ten requests a second, and wait:

```sh
kubectl -n obscapstone-demo exec deploy/tester -- sh -c \
  'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.1; done" >/dev/null 2>&1 &'
sleep 90
```

The 90 seconds matter: a `[1m]` rate window that still holds samples from before the load gives a watered-down answer.

## Step 2: Measure, do not sample

Divide the rate of `5xx` responses by the rate of all responses, from the client's side:

```sh
prom_query 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) / sum(rate(istio_requests_total{reporter="source"}[1m]))'
```

```text
{"metric":{},"value":[...,"0.39"]}
```

About `0.4`: a number, not "it fails sometimes". `=~` is a regular-expression match, so `"5.."` is any three-character code beginning with `5`. Dividing two sums gives a ratio that does not depend on traffic volume.

## Step 3: Read the reporter asymmetry

Group the rate by reporter and response code, then group the client-side errors by response flag:

```sh
prom_query 'sum(rate(istio_requests_total{destination_workload="notification-service-v1"}[1m])) by (reporter, response_code)'
prom_query 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) by (response_flags)'
```

```text
{"reporter":"destination","response_code":"200"} 6.0
{"reporter":"source","response_code":"200"}      6.0
{"reporter":"source","response_code":"503"}      3.9
```

**The missing fourth series is the finding.** There is no `destination` line for `503`: the server never received those requests. Every request is counted twice, once by each proxy, and the difference between the two views is the diagnosis:

| Pattern | Conclusion |
| --- | --- |
| errors in `source` only | never arrived — client-side configuration, connectivity, or the client's own limits |
| errors in both | arrived and failed there — destination policy or the application |

So the fault is in the client's proxy configuration, not in the service everyone blames.

## Step 4: Find every configuration fault

Run the analyzer and list the `VirtualService` objects with their hosts and gateways:

```sh
istioctl analyze -n obscapstone-demo
kubectl -n obscapstone-demo get virtualservice \
  -o custom-columns='NAME:.metadata.name,HOSTS:.spec.hosts,GATEWAYS:.spec.gateways'
```

```text
Error   [IST0101] (VirtualService notification-canary.obscapstone-demo) Referenced host+subset in destinationrule not found: "notification-service+canary"
Warning [IST0109] ... define the same host notification-service which can lead to undefined behavior.

NAME                    HOSTS                     GATEWAYS
notification            [notification-service]    <none>
notification-canary     [notification-service]    <none>
```

There are three faults, not one:

1. `notification` injects a fault that aborts 40% of requests with a `503`. You can see it with `kubectl -n obscapstone-demo get virtualservice notification -o yaml`.
2. `notification-canary` routes to a subset called `canary` that nothing defines.
3. Both objects claim the same host on the mesh gateway (an empty `GATEWAYS` column means the mesh), so which one wins is undefined.

## Step 5: Fix all three with one consolidation

Delete the canary object:

```sh
kubectl -n obscapstone-demo delete virtualservice notification-canary
```

Then replace `notification` with a plain route and no fault. Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: obscapstone-demo
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

You do not invent a `canary` subset. No pod carries such a label, and creating one would turn a loud `NC` failure (no cluster) into a quieter `UH` one (no healthy upstream).

Send it for grading to see where you stand:

```sh
astrona submit
```

## Step 6: Declare access logging

A `Telemetry` object holds the flight log settings for one namespace. With the `envoy` provider, every sidecar in `obscapstone-demo` writes one access log line per request.

Save this as `telemetry-access-logs.yaml`:

```yaml
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-logs
  namespace: obscapstone-demo
spec:
  accessLogging:
    - providers:
        - name: envoy
```

Apply it:

```sh
kubectl apply -f telemetry-access-logs.yaml
```

Metrics answer "how much, how bad, since when". Logs answer "what happened to *this* request". The `Telemetry` object is the scoped, easy-to-undo way to ask for the second without touching the install.

## Step 7: Prove it with the same query

Leave the load running, wait for the window to slide past the fault, then measure again, run the analyzer and send ten requests:

```sh
sleep 70
prom_query 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) / sum(rate(istio_requests_total{reporter="source"}[1m]))'
istioctl analyze -n obscapstone-demo
kubectl -n obscapstone-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -X POST http://notification-service/notify; done; echo'
```

```text
{"metric":{},"value":[...,"0"]}
✔ No validation issues found when analyzing namespace: obscapstone-demo.
200 200 200 200 200 200 200 200 200 200
```

**Counters keep their totals and rates forget.** The ratio falls to zero as the window slides past the fault; the history is not erased. That is the difference between reading a raw metric and reading a query over it.

## Step 8: Stop the load and submit

The grader checks four things: all three add-ons are `Running`; a `Telemetry` object in `obscapstone-demo` enables `envoy`; no `VirtualService` has a `fault` block and ten `POST` requests return `200`; and `istioctl analyze` is clean, exactly one `VirtualService` claims the host on the mesh gateway, and every `DestinationRule` subset selects a running pod.

```sh
kubectl -n obscapstone-demo exec deploy/tester -- pkill -f 'while true' || true
astrona submit
```

## Cross-checking Kiali

Every element in the Kiali page has a command behind it. Knowing the mapping lets you trust it in a hurry:

| Kiali shows | Check it with |
| --- | --- |
| an edge and its rate | `pilot-agent request GET stats/prometheus`, or a Prometheus query |
| edge colour | the same metric grouped by `response_code` |
| a padlock | `connection_security_policy` on the destination |
| a red validation badge | `istioctl analyze -n <ns>` |

Remember what a red edge says: *between this caller and this callee, a share of requests failed*. It does not say the callee is at fault. Here the failures were created entirely inside the caller's own proxy, and the `reporter` asymmetry in step 3 proved it from the data.

## Grafana

If your browser can reach the cluster, forward Grafana's port:

```sh
kubectl -n istio-system port-forward svc/grafana 3000:3000
```

Then open `http://localhost:3000` and choose by the question: **Istio Mesh** when you do not know the service, **Istio Service** for client and server views side by side, **Istio Workload** for inbound *and* outbound traffic, **Istio Control Plane** for push errors and rejects.

## Common mistakes

- Deciding a service is down because it is missing from the graph. Kiali draws traffic, not deployments.
- Installing Kiali without Prometheus, or assuming a `Running` Kiali can reach it.
- Forgetting `rate()` on a counter, or ignoring the `reporter` label and counting every request twice.
- Querying a window shorter than the scrape interval.
- Fixing the obvious fault injection and stopping. `istioctl analyze` had two more findings.
- Leaving the load generator running after the exercise.

## Practice variations

- Add `filter: { expression: "response.code >= 400" }` to the `Telemetry` object and confirm only failures are logged.
- Apply the fault again at 10% and see how much longer it takes to show in a `[5m]` window than in a `[1m]` one.
- Use the Control Plane dashboard to connect a configuration push with a latency spike.
