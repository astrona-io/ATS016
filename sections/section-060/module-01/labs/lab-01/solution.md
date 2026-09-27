# Solution: An Empty Graph And A Red Badge

## Step 1 — Check both data sources first

Kiali stores nothing. It reads Istio objects from the Kubernetes API and metrics
from Prometheus, and it fails quietly when either is missing:

```sh
kubectl -n istio-system get pods -l app=kiali
kubectl -n istio-system get pods -l app.kubernetes.io/name=prometheus
```

Both `Running`. So "the mesh is down" is not the explanation — and a Kiali that
is up with Prometheus missing would have produced exactly the same empty graph
with no error worth reading.

## Step 2 — Why an empty graph is normal here

The graph is built from `istio_requests_total` over a time window. No requests
in that window means no edges, and a node with no edges is not drawn. **An idle
service is invisible.**

Generate traffic and the picture appears:

```sh
kubectl -n kiali-demo exec deploy/tester -- sh -c \
  'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.2; done" >/dev/null 2>&1 &'
sleep 20
kubectl -n kiali-demo exec deploy/tester -c istio-proxy -- \
  pilot-agent request GET stats/prometheus \
  | grep istio_requests_total | grep 'destination_service_name="notification-service"' | head -2
```

```text
istio_requests_total{reporter="source",source_workload="tester",destination_workload="notification-service-v1",response_code="200",...} 98
```

That single series **is** one edge of the graph: a source workload, a
destination workload, a response code and a count. Five requests a second is
plenty — the graph needs continuity, not volume.

Allow for the pipeline delay: proxy → Prometheus scrape (~15s) → Kiali query.
A new edge takes tens of seconds to appear even when everything works.

## Step 3 — Find what the validation badge is about

Kiali's Istio Config view runs the same analyzers as `istioctl analyze` and
reports the same codes, so confirm it from the terminal:

```sh
istioctl analyze -n kiali-demo
```

```text
Error [IST0101] (VirtualService broken.kiali-demo) Referenced gateway not found: "does-not-exist"
Error [IST0101] (VirtualService broken.kiali-demo) Referenced host+subset in destinationrule not found: "notification-service+nonexistent"
Warning [IST0109] (VirtualService broken.kiali-demo) ... define the same host notification-service which can lead to undefined behavior.
```

Three findings on one object, and the third is a bonus lesson: adding a second
`VirtualService` for a host that already had one reproduced the host-ownership
conflict from section 020.

## Step 4 — Fix them

The `broken` object references a gateway that does not exist, a subset that does
not exist, and duplicates a host that already has an owner. Nothing about it is
salvageable — remove it, and make sure a valid route for the host remains:

```sh
kubectl -n kiali-demo delete virtualservice broken
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: kiali-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
EOF
istioctl analyze -n kiali-demo
```

```text
✔ No validation issues found when analyzing namespace: kiali-demo.
```

Note what was **not** done: no `Gateway` called `does-not-exist` was created,
and no `nonexistent` subset was invented. Making a dangling reference resolve by
creating its target is how you trade a loud failure for a quiet one.

```sh
astrona submit
```

## Step 5 — Read the graph as a locator

In the UI (`kubectl -n istio-system port-forward svc/kiali 20001:20001`), set
graph type and time range deliberately, and turn on **Traffic rate**,
**Security** and **Idle nodes**.

A red edge states one thing precisely: *between this caller and this callee, in
this window, a significant share of requests failed.* It does **not** say the
callee is at fault — the failure may be a `503` the caller's own proxy generated
without ever contacting it. The graph tells you **where** to look; the access
log tells you **why**.

Everything Kiali shows has a command behind it:

| Kiali shows | Check it with |
| --- | --- |
| an edge and its rate | `pilot-agent request GET stats/prometheus` |
| edge colour | the same metric grouped by `response_code` |
| a padlock | `connection_security_policy` on the destination |
| a red validation badge | `istioctl analyze -n <ns>` |

```sh
astrona submit
```

## Cleaning up the load generator

```sh
kubectl -n kiali-demo exec deploy/tester -- pkill -f 'while true' || true
```

## Common mistakes

- Installing Kiali without Prometheus. The graph stays empty and nothing
  explains why.
- Concluding a service is down because it is missing from the graph. Kiali draws
  traffic, not deployments.
- Trusting a stale view. The graph has a time window; widen it or refresh after
  generating load.
- Using Kiali as the only evidence. Confirm findings with `istioctl` before
  changing anything.

## Practice variations

- Use the graph to find which caller is responsible when two clients exist.
- Compare Kiali's validation list with `istioctl analyze --all-namespaces`.
- Apply `manifests/fault.yaml`, watch the edge turn red, and correlate the
  percentage with the raw `response_code` counters.
