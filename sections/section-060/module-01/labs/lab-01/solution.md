# Solution: An Empty Graph And A Red Badge

The graph is empty because nothing has sent any traffic, and the red validation icon is on a `VirtualService` that points at things that do not exist. You fix the second one and prove both with the command line, which reads the same data Kiali draws from.

## Step 1: Check both data sources first

Kiali stores nothing. It reads Istio objects from the Kubernetes API server and metrics from Prometheus, and it fails quietly when either one is missing. Check both pods:

```sh
kubectl -n istio-system get pods -l app=kiali
kubectl -n istio-system get pods -l app.kubernetes.io/name=prometheus
```

Both are `Running`. So "the mesh is down" is not the explanation. A Kiali that runs with Prometheus missing would show exactly the same empty graph, with no useful error.

What each source gives Kiali:

- **The Kubernetes API server:** the Istio objects, Services and Pods. Kiali uses them for the Istio Config view and the Workloads and Services lists.
- **Prometheus:** the `istio_requests_total` metrics. Kiali uses them to draw nodes and edges.

## Step 2: Understand why an empty graph is normal here

The graph is built from `istio_requests_total` over a time window. No requests in that window means no edges, and a node with no edges is not drawn. **An idle service is invisible.**

Send steady traffic from the `tester` pod (a background loop, five requests a second), wait 20 seconds, and read the counters from the tester's own proxy:

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

That one series **is** one edge of the graph: a source workload, a destination workload, a response code and a count. Five requests a second is plenty. The graph needs traffic that keeps going, not a lot of it.

Allow for the delay along the way: the proxy, then a Prometheus scrape about every 15 seconds, then the Kiali query. A new edge takes tens of seconds to appear even when everything works.

## Step 3: Find what the validation icon is about

Kiali's Istio Config view runs the same analyzers as `istioctl analyze` and reports the same `IST####` codes. Confirm it from the terminal:

```sh
istioctl analyze -n kiali-demo
```

```text
Error [IST0101] (VirtualService broken.kiali-demo) Referenced gateway not found: "does-not-exist"
Error [IST0101] (VirtualService broken.kiali-demo) Referenced host+subset in destinationrule not found: "notification-service+nonexistent"
```

The output is shortened to the two messages. They are the red icon: the `VirtualService` named `broken` names a `Gateway` called `does-not-exist` and a subset called `nonexistent`, and neither exists. Both are references between objects, which is why the API server accepted the object: its validating webhook only ever sees one object at a time.

## Step 4: Fix them

The `broken` object points at a gateway that does not exist and a subset that does not exist. Nothing in it is worth keeping. Remove it:

```sh
kubectl -n kiali-demo delete virtualservice broken
```

The grader also requires a valid route for the host to remain, so the namespace is still routed. Save this as `virtualservice-notification.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

Then check the result:

```sh
istioctl analyze -n kiali-demo
```

```text
✔ No validation issues found when analyzing namespace: kiali-demo.
```

Look at what you did **not** do. You did not create a `Gateway` called `does-not-exist`, and you did not invent a `nonexistent` subset. Making a dangling reference resolve by creating its target trades a loud failure for a quiet one.

Send it for grading to see where you stand:

```sh
astrona submit
```

## Step 5: Read the graph as a locator

If your browser can reach the cluster, open the Kiali page:

```sh
kubectl -n istio-system port-forward svc/kiali 20001:20001
```

Then open `http://localhost:20001`. Set the graph type and time range on purpose, and turn on **Traffic rate**, **Security** and **Idle nodes**.

A red edge says one thing exactly: *between this caller and this callee, in this window, a large share of requests failed.* It does **not** say the callee is at fault. The failure may be a `503` the caller's own sidecar proxy created without ever contacting it. The graph tells you **where** to look. The access log tells you **why**.

Everything Kiali shows has a command behind it:

| Kiali shows | Check it with |
| --- | --- |
| an edge and its rate | `pilot-agent request GET stats/prometheus` |
| edge colour | the same metric grouped by `response_code` |
| a padlock | `connection_security_policy` on the destination |
| a red validation icon | `istioctl analyze -n <ns>` |

## Step 6: Submit

The grader checks three things: the Prometheus and Kiali pods are `Running`; `istioctl analyze -n kiali-demo` reports no `Error` or `Warning` and a `VirtualService` still routes `notification-service`; and the tester's proxy holds `istio_requests_total` series for the `tester` to `notification-service` edge. The grader sends five requests of its own before it checks the metrics.

```sh
astrona submit
```

When you are done, stop the load generator:

```sh
kubectl -n kiali-demo exec deploy/tester -- pkill -f 'while true' || true
```

## Common mistakes

- Installing Kiali without Prometheus. The graph stays empty and nothing explains why.
- Deciding a service is down because it is missing from the graph. Kiali draws traffic, not deployments.
- Trusting an old view. The graph has a time window. Widen it, or refresh after you send traffic.
- Using Kiali as the only evidence. Confirm findings with `istioctl` before you change anything.
- Deleting every `VirtualService` to clear the findings. The grader requires a route for `notification-service` to remain.

## Practice variations

- Use the graph to find which caller is responsible when two clients exist.
- Compare Kiali's validation list with `istioctl analyze --all-namespaces`.
- Apply a `VirtualService` that aborts 30% of requests with a `500`, watch the edge turn red, and compare the percentage with the raw `response_code` counters.
