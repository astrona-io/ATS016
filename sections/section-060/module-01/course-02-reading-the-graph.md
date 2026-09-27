# Part 2 — Reading The Graph

> Prerequisite: [Part 1 — What Kiali Is Built From](./course-01-what-kiali-is-built-from.md). Next: [Part 3 — Validations, Badges And Cross-Checking](./course-03-validations-and-cross-checking.md).

The graph is the reason people open Kiali, and it is easy to over-read. This part is what each element states precisely: what a node is, what an edge measures, what a colour means, and the three reasons a service you expect is not on the screen.

## Nodes are a choice, not a fact

The same traffic can be drawn at four different granularities, and the **graph type** selector decides which:

| Graph type | A node is | Use it for |
| --- | --- | --- |
| **Workload** | a Deployment | "which deployment is failing" — the most operationally direct |
| **Service** | a Kubernetes Service | "which service is failing", ignoring versions |
| **Versioned app** | an app, split by `version` label | canary and A/B analysis — the default |
| **App** | an app, versions merged | a simpler business-level view |

They are projections of the same metric series, grouped by different labels. A canary problem that is obvious in *versioned app* — one version red, the other green — disappears in *app*, where the two are summed. Choosing the wrong granularity is a way to look straight at a problem and not see it.

Note what makes the version split possible: the `version` label on your pods. Istio's telemetry reads it, so the convention that feels like boilerplate in a Deployment manifest is what makes canary analysis legible here.

## Edges measure a rate over a window

An edge exists when the selected window contains requests between two nodes. Two controls change what you see more than anything else on the screen:

- **The time range** (last 1m, 5m, 30m, …) — the window the rate is computed over.
- **The refresh interval** — how often the query is re-run.

A short window is responsive and noisy; a long one is stable and hides brief incidents. When something "cleared up by itself", widen the window before believing it — and when an edge is flickering, narrow it to see whether the traffic is genuinely intermittent.

An edge also **fades out after traffic stops**. Counters in Prometheus keep their totals, but a *rate* over a window that no longer contains requests goes to zero, and a zero-rate edge is not drawn. That is why the graph goes quiet a minute or two after a load generator stops, and it is not a bug.

## Display options worth turning on

| Option | Adds | Answers |
| --- | --- | --- |
| **Traffic rate** | requests/second on each edge, coloured by error rate | where is the traffic, and where is it failing |
| **Security** | a padlock on mTLS edges | which paths are encrypted ([Part 3](./course-03-validations-and-cross-checking.md)) |
| **Response time** | a latency percentile on each edge | where is the slowness, as opposed to the errors |
| **Traffic animation** | moving dots along edges | direction of flow; the fastest way to spot a call you did not know existed |
| **Idle nodes** | nodes with no traffic in the window | what *should* be there but is silent |

**Idle nodes** deserves special mention: turning it on converts "this service is missing" into "this service is present and receiving nothing", which are different problems with different causes. It is the single most useful toggle for the confusion this part ends with.

## What a red edge states

A red edge is a precise claim and a limited one:

> Between this caller and this callee, in the selected window, a significant proportion of requests ended with an error status.

What it does **not** say:

- **Not that the callee is at fault.** The failure may be a `503` the *caller's own proxy* generated without ever contacting the callee — every `NC`, `UH`, `UO` and `UT` from [module 050-01](../../section-050/module-01/course-03-flags-and-which-proxy.md) is exactly that.
- **Not which failure it is.** Error rate is a count of statuses, not a diagnosis.
- **Not that it is happening now.** It is an average over the window.

So the graph is a **locator**. It names the pair of workloads to investigate; the access log on the caller names the layer; `proxy-config` names the misconfiguration. Treating a red edge as a conclusion — "the notification service is broken" — is how a team spends an afternoon on a service that was healthy throughout.

## Making an edge turn red

Fault injection gives a controlled, known error rate, which is the honest way to learn what the graph looks like when something is wrong.

> [!TIP]
> **Try it — 30% of requests failing**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: notification
>   namespace: kiali-demo
> spec:
>   hosts:
>     - notification-service
>   http:
>     - fault:
>         abort:
>           httpStatus: 500
>           percentage:
>             value: 30
>       route:
>         - destination:
>             host: notification-service
> EOF
> sleep 30
> kubectl -n kiali-demo exec deploy/tester -c istio-proxy -- \
>   pilot-agent request GET stats/prometheus \
>   | grep istio_requests_total | grep -o 'response_code="[0-9]*"' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
>    1 response_code="200"
>    1 response_code="500"
> ```
>
> Two counter **series** now exist where there was one — the proxy tracks each status code separately, and the ratio between their rates is the number Kiali turns into a colour. In the UI this edge is now red.
>
> Note where the abort was injected: by the **client's** proxy, per [module 050-01 Part 4](../../section-050/module-01/course-04-producing-each-failure.md). The destination never received these requests, and its own metrics will not show the `500`s at all — which is a concrete instance of "a red edge does not mean the callee is at fault", visible in the underlying data.

## Why a service might be missing

Three explanations, in the order worth checking:

```text
   1. No traffic in the selected window.
         → widen the time range, enable Idle nodes, or generate load.     (usual answer)

   2. No sidecar.
         → no metrics are produced at all, so nothing can draw it.
           check: READY 2/2 vs 1/1  (module 030-03)

   3. Prometheus is not scraping it.
         → affects whole namespaces rather than single workloads.
           check: does the proxy have the metric? does Prometheus?
```

Kiali's **Workloads** and **Services** lists are more useful than the graph for this, because they are built from **Kubernetes objects** rather than from metrics. A workload with no traffic still appears there, flagged with a health reason — "no running pods", "missing sidecar", "no traffic". Moving between the graph and those lists is how you tell "absent from the mesh" from "absent from the traffic".

That difference in data source is the thing to remember: the graph is metrics, the lists are the API server, and only one of them can show you something that is not sending requests.

> [!WARNING]
> **Pitfalls in reading the graph**
>
> - **Reading a red edge as "the callee is broken".** It means requests between that pair failed. The failure may have occurred entirely inside the caller's proxy.
> - **Leaving the graph type on the default.** A canary problem visible in *versioned app* vanishes in *app*, where versions are summed.
> - **Forgetting the time window.** An edge is a rate over a range; widen it before concluding an incident is over.
> - **Concluding a service is missing from the mesh because it is missing from the graph.** Check Idle nodes and the Workloads list before anything else.
> - **Expecting an edge to disappear instantly after a fix.** Rates decay over the window; give it a minute.
> - **Using the graph to diagnose rather than to locate.** It has no information about *why* — that is the access log's job.

> *An edge is a rate over a window between two nodes you chose the granularity of — every one of those words is a way to look at the wrong picture.*

## Reference

- [Kiali graph](https://kiali.io/docs/features/topology/) — graph types, display options and the meaning of each badge.
- [Kiali health](https://kiali.io/docs/features/health/) — how the Workloads and Services lists compute health, and why they differ from the graph.
- [Fault injection](https://istio.io/latest/docs/tasks/traffic-management/fault-injection/) — the `abort` percentage used above.
- [Istio standard metrics](https://istio.io/latest/docs/reference/config/metrics/) — the `response_code` and `version` labels behind edge colour and graph type.
