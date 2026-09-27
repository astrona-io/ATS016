# Solution: Measure A Failure, Fix It, Prove It

Define the query helper first — every measurement below uses the Prometheus HTTP
API from inside the cluster, so no browser is required:

```sh
Q() { kubectl -n obscapstone-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' --data-urlencode "query=$1"; echo; }
```

## Step 1 — The empty graph is not an outage

```sh
kubectl -n istio-system get pods -l app=kiali
kubectl -n istio-system get pods -l app.kubernetes.io/name=prometheus
kubectl -n istio-system get pods -l app.kubernetes.io/name=grafana
```

All `Running`. Kiali stores nothing — it reads Istio objects from the API server
and metrics from Prometheus — so an empty graph means one of two things, and
"the mesh is down" is neither of them.

The graph is built from `istio_requests_total` over a time window. **No requests
in the window means no edges, and a node with no edges is not drawn.** An idle
service is invisible.

```sh
kubectl -n obscapstone-demo exec deploy/tester -- sh -c \
  'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.1; done" >/dev/null 2>&1 &'
sleep 90
```

Ninety seconds: a `[1m]` rate window still containing pre-load samples reports a
diluted answer, and reading too early is the commonest way to disbelieve a
correct query.

## Step 2 — Measure, do not sample

```sh
Q 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) / sum(rate(istio_requests_total{reporter="source"}[1m]))'
```

```text
{"metric":{},"value":[...,"0.39"]}
```

About `0.4` — a number, not "it fails sometimes". `=~` is a regex match, so
`"5.."` is any three-character code beginning with `5`, and dividing two sums
gives a ratio independent of traffic volume.

## Step 3 — Read the reporter asymmetry

```sh
Q 'sum(rate(istio_requests_total{destination_workload="notification-service-v1"}[1m])) by (reporter, response_code)'
Q 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) by (response_flags)'
```

```text
{"reporter":"destination","response_code":"200"} 6.0
{"reporter":"source","response_code":"200"}      6.0
{"reporter":"source","response_code":"503"}      3.9
```

**The missing fourth series is the finding.** There is no `destination` line for
`503`: the server never received those requests. Every request is counted twice —
once by each proxy — and the difference between the two views is the diagnostic:

| Pattern | Conclusion |
| --- | --- |
| errors in `source` only | never arrived — client-side config, connectivity, or the client's own limits |
| errors in both | arrived and failed there — destination policy or the application |

So the fault is in the client's proxy configuration, not in the service everyone
is blaming.

## Step 4 — Find every configuration fault

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

Three faults, not one:

1. a 40% abort fault injected by `notification`;
2. `notification-canary` routes to a subset nothing defines;
3. both objects claim the same host on the mesh gateway, so the merge order is
   undefined.

## Step 5 — Fix all three with one consolidation

```sh
kubectl -n obscapstone-demo delete virtualservice notification-canary
kubectl apply -f - <<'EOF'
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
EOF
```

No `canary` subset is invented: no pod carries such a label, and creating one
would turn a loud `NC` failure into a quieter `UH` one.

```sh
astrona submit
```

## Step 6 — Declare access logging

```sh
kubectl apply -f - <<'EOF'
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-logs
  namespace: obscapstone-demo
spec:
  accessLogging:
    - providers:
        - name: envoy
EOF
```

Metrics answer "how much, how bad, since when". Logs answer "what happened to
*this* request". The `Telemetry` object is the scoped, revertible way to ask for
the second without touching the install.

## Step 7 — Prove it with the same query

```sh
sleep 70
Q 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) / sum(rate(istio_requests_total{reporter="source"}[1m]))'
istioctl analyze -n obscapstone-demo
kubectl -n obscapstone-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -X POST http://notification-service/notify; done; echo'
```

```text
{"metric":{},"value":[...,"0"]}
✔ No validation issues found when analyzing namespace: obscapstone-demo.
200 200 200 200 200 200 200 200 200 200
```

**Counters keep their totals and rates forget** — the ratio falls to zero as the
window slides past the fault, rather than the history being erased. That is the
difference between reading a raw metric and reading a query over it.

Stop the load generator:

```sh
kubectl -n obscapstone-demo exec deploy/tester -- pkill -f 'while true' || true
astrona submit
```

## Cross-checking Kiali

Every element in the UI has a command behind it. Knowing the mapping is what
lets you trust it in a hurry:

| Kiali shows | Check it with |
| --- | --- |
| an edge and its rate | `pilot-agent request GET stats/prometheus`, or a Prometheus query |
| edge colour | the same metric grouped by `response_code` |
| a padlock | `connection_security_policy` on the destination |
| a red validation badge | `istioctl analyze -n <ns>` |

And remember what a red edge states: *between this caller and this callee, a
share of requests failed*. Not that the callee is at fault — here the failures
were generated entirely inside the caller's own proxy, which the `reporter`
asymmetry in step 3 proved from the data.

## Grafana

`kubectl -n istio-system port-forward svc/grafana 3000:3000`, then choose by the
question: **Istio Mesh** when you do not know the service, **Istio Service** for
client and server views side by side, **Istio Workload** for inbound *and*
outbound traffic, **Istio Control Plane** for push errors and rejects.

## Common mistakes

- Concluding a service is down because it is missing from the graph. Kiali draws
  traffic, not deployments.
- Installing Kiali without Prometheus, or assuming a `Running` Kiali can reach
  it.
- Forgetting `rate()` on a counter, or ignoring the `reporter` label and double
  counting every request.
- Querying a window shorter than the scrape interval.
- Fixing the obvious fault injection and stopping — `istioctl analyze` had two
  more findings.
- Leaving the load generator running after the exercise.

## Practice variations

- Add `filter: { expression: "response.code >= 400" }` to the `Telemetry` object
  and confirm only failures are logged.
- Re-apply the fault at 10% and see how much longer it takes to be visible in a
  `[5m]` window than a `[1m]` one.
- Use the Control Plane dashboard to correlate a config push with a latency
  spike.
