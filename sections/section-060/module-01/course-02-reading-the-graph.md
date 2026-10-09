# Reading The Graph

The graph is why people open Kiali, and it is easy to read too much into it. A node depends on a setting you choose, an edge is an average over a time window, and a colour counts status codes without saying who caused them. This part explains what each piece of the graph says, turns an edge red on purpose with a known error rate, and explains why a service you expect can be missing.

## Nodes are a choice, not a fact

Kiali can draw the same traffic at four levels of detail. The **graph type** selector decides which one you see:

| Graph type | A node is | Use it for |
| --- | --- | --- |
| **Workload** | a Deployment | "which Deployment is failing"; the most direct view for operations |
| **Service** | a Kubernetes Service | "which Service is failing", ignoring versions |
| **Versioned app** | an app, split by its `version` label | canary analysis: comparing two versions |
| **App** | an app, versions merged | a simpler view of the whole application |

All four come from the same metrics, grouped by different labels. Take a canary release, where a new version of a workload gets a small share of the requests first. In *versioned app* the problem is obvious: one version red, the other green. In *app* the two versions are added together, and the problem disappears. With the wrong graph type you can look straight at a problem and not see it.

The version split works because of the `version` label on your pods. Istio copies it into the metrics. So that label, which looks like a formality in a Deployment, is what makes canary analysis readable here.

## Edges measure a rate over a window

An edge exists when the chosen time window contains requests between two nodes. Two controls change what you see more than anything else. The **time range** (last 1m, 5m, 30m, and so on) is the window Kiali averages the rate over. The **refresh interval** is how often Kiali runs the query again.

A short window reacts fast but jumps around. A long window is steady but hides short incidents. When a problem "cleared up by itself", widen the window before you believe it. When an edge flickers, narrow the window to see whether the traffic really comes and goes.

An edge also **fades out after traffic stops**. Prometheus keeps the totals, but the *rate* over a window with no requests in it drops to zero, and Kiali does not draw a zero-rate edge. That is why the graph goes quiet a minute or two after a load generator stops. It is not a bug.

## Display options worth turning on

The display menu adds information to the graph. These five options answer the questions you ask most often:

| Option | Adds | Answers |
| --- | --- | --- |
| **Traffic rate** | requests per second on each edge, coloured by error rate | where is the traffic, and where is it failing |
| **Security** | a padlock on edges that used mTLS | which paths are encrypted |
| **Response time** | a latency percentile on each edge | where is the slowness, as opposed to the errors |
| **Traffic animation** | moving dots along edges | direction of flow; the fastest way to spot a call you did not know existed |
| **Idle nodes** | nodes with no traffic in the window | what *should* be there but is silent |

**Idle nodes** is the most useful of them. It turns "this service is missing" into "this service is here and receives nothing". Those are two different problems with different causes.

## What a red edge says

A red edge makes one exact claim, and only one:

> Between this caller and this callee, in the selected window, a significant share of requests ended with an error status.

It does **not** say that the callee is at fault. The failure may be a `503` that the *caller's own sidecar proxy* created without ever contacting the callee. The access log is the log the proxy writes with one line per request, and each failed line carries a response flag: a short Envoy code that says why the request failed. The flags `NC` (no cluster found), `UH` (no healthy upstream), `UO` (upstream overflow, from a circuit breaker) and `UT` (upstream request timeout) all mean the caller's proxy stopped the request. A red edge also does not say which failure it is, because an error rate counts status codes. And it does not say the failure is happening now, because it is an average over the window.

So the graph is a **locator**. It names the pair of workloads to look at. The access log on the caller names the layer that failed, and `istioctl proxy-config` shows the wrong setting. If you treat a red edge as the answer ("the notification service is broken"), you can spend an afternoon on a service that was healthy the whole time.

## Making an edge turn red

Fault injection is a `VirtualService` feature that makes the sidecar proxy fail or delay a share of requests on purpose. It gives a known error rate, which is the honest way to learn what the graph looks like when something is wrong.

The background traffic loop in the `tester` pod must be running for this step. If you stopped it, or have not started it yet, start it now:

<!-- astrona:playground:renew -->

```sh
kubectl -n kiali-demo exec deploy/tester -- sh -c \
  'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.2; done" >/dev/null 2>&1 &'
```

The `VirtualService` below tells the caller's sidecar proxy to answer 30% of requests for `notification-service` with a `500` instead of sending them on.

Save this as `virtualservice-notification.yaml`:

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
    - fault:
        abort:
          httpStatus: 500
          percentage:
            value: 30
      route:
        - destination:
            host: notification-service
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

Then check the result. Wait 30 seconds, and count the response codes in the `tester` pod's proxy metrics:

```sh
sleep 30
kubectl -n kiali-demo exec deploy/tester -c istio-proxy -- \
  pilot-agent request GET stats/prometheus \
  | grep istio_requests_total | grep -o 'response_code="[0-9]*"' | sort | uniq -c
```

You should see something like:

```text
   1 response_code="200"
   1 response_code="500"
```

Two counter **series** now exist where there was one, because the proxy keeps a separate counter for each status code. The ratio between their rates is the number Kiali turns into a colour, so in the Kiali page this edge is now red.

Look at where the fault happens: in the **caller's** proxy. The `tester` pod's sidecar proxy answers with the `500` itself. The destination never received these requests, and its own metrics do not show the `500`s at all. That is "a red edge does not mean the callee is at fault", visible in the raw data.

## Why a service might be missing

When a service you expect is not in the graph, there are three likely reasons. Check them in this order:

1. **No traffic in the chosen window.** This is the usual answer. Widen the time range, turn on Idle nodes, or send traffic.
2. **No sidecar.** A pod with no sidecar proxy produces no metrics at all, so nothing can draw it. Check the `READY` column: `2/2` has a sidecar, `1/1` has none.
3. **Prometheus is not collecting its metrics.** This usually hits whole namespaces, not single workloads. Check whether the proxy has the metric, then whether Prometheus has it.

Kiali's **Workloads** and **Services** lists help more than the graph here. They are built from **Kubernetes objects**, not from metrics. A workload with no traffic still appears there, with a health reason such as "no running pods", "missing sidecar" or "no traffic". Switching between the graph and those lists tells "not in the mesh" apart from "not in the traffic". The graph comes from metrics and the lists come from the API server, so only the lists can show you something that sends no requests.

You can now read the graph for what it is: nodes at a level of detail you chose, edges that are rates over a window, and colours that count status codes. A red edge locates a pair of workloads; it does not blame the callee, and fault injection proved that the failure can live entirely in the caller's proxy. What remains is the other half of Kiali, the part that reads Istio objects instead of metrics.

## Common pitfalls

> [!WARNING]
> - **Reading a red edge as "the callee is broken".** It means requests between that pair failed. The failure may have happened entirely inside the caller's proxy.
> - **Leaving the graph type on the wrong level.** A canary problem that shows in *versioned app* disappears in *app*, where versions are added together.
> - **Forgetting the time window.** An edge is a rate over a range. Widen it before you decide an incident is over.
> - **Deciding a service is not in the mesh because it is not in the graph.** Check Idle nodes and the Workloads list first.
> - **Expecting an edge to change the moment you fix something.** Rates change over the window. Give it a minute.
> - **Using the graph to diagnose instead of to locate.** It cannot tell you *why*. That is the access log's job.
