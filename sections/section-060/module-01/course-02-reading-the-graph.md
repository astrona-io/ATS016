# Reading The Graph

The graph is why people open Kiali, the tactical map in mission control, and it is easy to read too much into it. This part explains exactly what each piece of the map says: what a node is, what an edge measures, what a colour means, and why a service you expect can be missing from the screen.

## Nodes are a choice, not a fact

Kiali can draw the same traffic at four levels of detail. The **graph type** selector decides which one you see:

| Graph type | A node is | Use it for |
| --- | --- | --- |
| **Workload** | a Deployment | "which deployment is failing" — the most operationally direct |
| **Service** | a Kubernetes Service | "which service is failing", ignoring versions |
| **Versioned app** | an app, split by `version` label | canary and A/B analysis — the default |
| **App** | an app, versions merged | a simpler business-level view |

All four come from the same metrics, grouped by different labels. Picture a canary release, where a new ship class gets a small share of signals first. In *versioned app* the problem is obvious: one version red, the other green. In *app* the two versions are added together, and the problem disappears. With the wrong graph type you can look straight at a problem and not see it.

The version split works because of the `version` label on your pods. Istio's metrics read it. So that label, which looks like boilerplate in a Deployment, is what makes canary analysis readable here.

## Edges measure a rate over a window

An edge exists when the chosen time window contains requests between two nodes. Two controls change what you see more than anything else:

- **The time range** (last 1m, 5m, 30m, …): the window Kiali averages the rate over.
- **The refresh interval:** how often Kiali runs the query again.

A short window reacts fast but jumps around. A long window is steady but hides short incidents. When a problem "cleared up by itself", widen the window before you believe it. When an edge flickers, narrow the window to see whether the traffic really comes and goes.

An edge also **fades out after traffic stops**. Prometheus keeps the totals, but the *rate* over a window with no requests in it drops to zero, and Kiali does not draw a zero-rate edge. That is why the map goes quiet a minute or two after a load generator stops. It is not a bug.

## Display options worth turning on

The display menu adds information to the map. These five options answer the questions you ask most often:

| Option | Adds | Answers |
| --- | --- | --- |
| **Traffic rate** | requests/second on each edge, coloured by error rate | where is the traffic, and where is it failing |
| **Security** | a padlock on mTLS edges | which paths are encrypted |
| **Response time** | a latency percentile on each edge | where is the slowness, as opposed to the errors |
| **Traffic animation** | moving dots along edges | direction of flow; the fastest way to spot a call you did not know existed |
| **Idle nodes** | nodes with no traffic in the window | what *should* be there but is silent |

**Idle nodes** is the most useful of them. It turns "this service is missing" into "this service is here and receives nothing". Those are two different problems with different causes.

## What a red edge says

A red edge makes one exact claim, and only one:

> Between this caller and this callee, in the selected window, a significant proportion of requests ended with an error status.

Here is what it does **not** say:

- **Not that the callee is at fault.** The failure may be a `503` that the *caller's own proxy* created without ever contacting the callee. Response flags such as `NC` (no cluster), `UH` (no healthy upstream), `UO` (overflow, a circuit breaker) and `UT` (timeout) all mean exactly that. A response flag is the short code the communications officer stamps on a failed signal in the flight log (the access log).
- **Not which failure it is.** An error rate counts status codes. It is not a diagnosis.
- **Not that it is happening now.** It is an average over the window.

So the graph is a **locator**. It names the pair of workloads to look at. The access log on the caller names the layer that failed. `istioctl proxy-config` names the wrong setting. If you treat a red edge as the answer ("the notification service is broken"), you can spend an afternoon on a service that was healthy the whole time.

## Making an edge turn red

Fault injection is a training drill: you tell the mesh to fail some signals on purpose. It gives a known error rate, which is the honest way to learn what the map looks like when something is wrong.

The background traffic loop in the `tester` pod must be running for this step. If you stopped it, or have not started it yet, start it now:

<!-- astrona:playground:renew -->

```sh
kubectl -n kiali-demo exec deploy/tester -- sh -c \
  'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.2; done" >/dev/null 2>&1 &'
```

### Make 30% of requests fail

This `VirtualService` (the flight plan for the beacon) tells the caller's proxy to answer 30% of requests with a `500` instead of sending them on.

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

Then check the result. Wait 30 seconds, and count the response codes in the tester's proxy metrics:

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

Two counter **series** now exist where there was one. The proxy keeps a separate counter for each status code. The ratio between their rates is the number Kiali turns into a colour, so in the Kiali page this edge is now red.

Look at where the drill happens: in the **caller's** proxy. The `tester` ship's communications officer answers with the `500` itself. The destination never received these requests, and its own metrics do not show the `500`s at all. That is "a red edge does not mean the callee is at fault", visible in the raw data.

## Why a service might be missing

When a service you expect is not on the map, there are three likely reasons. Check them in this order:

1. **No traffic in the chosen window.** This is the usual answer. Widen the time range, turn on Idle nodes, or send traffic.
2. **No sidecar.** A ship with no communications officer produces no metrics at all, so nothing can draw it. Check the `READY` column: `2/2` has a sidecar, `1/1` has none.
3. **Prometheus is not collecting its metrics.** This usually hits whole namespaces, not single workloads. Check whether the proxy has the metric, then whether Prometheus has it.

Kiali's **Workloads** and **Services** lists help more than the graph here. They are built from **Kubernetes objects**, not from metrics. A workload with no traffic still appears there, with a health reason such as "no running pods", "missing sidecar" or "no traffic". Switching between the graph and those lists tells "not in the mesh" apart from "not in the traffic".

Remember the difference in data source: the graph is metrics, the lists are the API server. Only the lists can show you something that sends no requests.

## Common pitfalls

> [!WARNING]
> - **Reading a red edge as "the callee is broken".** It means requests between that pair failed. The failure may have happened entirely inside the caller's proxy.
> - **Leaving the graph type on the default.** A canary problem that shows in *versioned app* disappears in *app*, where versions are added together.
> - **Forgetting the time window.** An edge is a rate over a range. Widen it before you decide an incident is over.
> - **Deciding a service is not in the mesh because it is not on the graph.** Check Idle nodes and the Workloads list first.
> - **Expecting an edge to change the moment you fix something.** Rates change over the window. Give it a minute.
> - **Using the graph to diagnose instead of to locate.** It cannot tell you *why*. That is the access log's job.

> *An edge is a rate over a window between two nodes whose level of detail you chose, and each of those words is a way to look at the wrong picture.*
