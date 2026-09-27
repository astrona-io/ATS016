# Part 1 — What Kiali Is Built From

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — Reading The Graph](./course-02-reading-the-graph.md).

Kiali looks like a monitoring system and is not one. Understanding what it actually reads decides how much to trust each thing it shows — and explains, in advance, every way it can appear broken when nothing is wrong.

## Two inputs, no storage

```text
   Kubernetes API ──── Istio objects ─────┐
   (VirtualService, DestinationRule,      │
    Gateway, policies, Services, Pods)    │
                                          ▼
                                    ┌──────────┐
                                    │  Kiali   │  stateless: no database,
                                    │          │  no agents, no collection
                                    └──────────┘
                                          ▲
   Prometheus ──── istio_* metrics ───────┘
   (scraped from each proxy's :15090)
```

Kiali holds no data of its own. Every request it serves is answered by querying one or both of those sources live. Three consequences, and they explain most "Kiali is broken" reports:

- **No Prometheus, no graph.** The topology is computed from metrics. Without them Kiali still lists workloads and validates configuration, but the graph is empty.
- **No traffic, no graph.** Even with Prometheus healthy, an edge exists only if requests were recorded in the selected window. An idle service has no edges and is not drawn.
- **Nothing it shows is Kiali's opinion.** Every number came from a proxy; every validation came from an analyzer. You can go and check any of it, which is what [Part 3](./course-03-validations-and-cross-checking.md) does.

> [!TIP]
> **Try it — the two dependencies**
>
> ```sh
> kubectl -n istio-system get pods -l app=kiali
> kubectl -n istio-system get pods -l app.kubernetes.io/name=prometheus
> ```
>
> Expect something like:
>
> ```text
> NAME                     READY   STATUS    RESTARTS   AGE
> kiali-5d7f8b6c4-t9wqx    1/1     Running   0          8m
> 
> NAME                          READY   STATUS    RESTARTS   AGE
> prometheus-7c9b8d5f4-k3m2p    2/2     Running   0          8m
> ```
>
> Both must be `Running`. A Kiali that is up with Prometheus missing produces an empty graph and no error worth reading — the single most common "Kiali is broken" report, and it is not Kiali that is broken. Note that Kiali being `1/1` tells you nothing about whether it can *reach* Prometheus; its own configuration names the Prometheus URL, and a wrong URL fails exactly as silently.

## From a metric to an edge

The graph is a query, not a topology map. Kiali asks Prometheus for `istio_requests_total` over a time range, grouped by the labels that identify both ends of each call:

```text
   istio_requests_total{
     reporter="destination",
     source_workload="tester",            source_workload_namespace="kiali-demo",
     destination_workload="notification-service-v1",
     destination_service_name="notification-service",
     response_code="200",
     connection_security_policy="mutual_tls"
   }  98
        │
        ▼
   node("tester") ──edge: 5.2 req/s, 0% error, 🔒──▶ node("notification-service")
```

Each label group with a non-zero rate becomes an edge; the workloads become nodes; the response codes become the colour; `connection_security_policy` becomes the padlock. The graph is, quite literally, a `sum(rate(...)) by (source, destination, ...)` drawn with arrows.

That mapping is worth internalising because it explains every limitation of the graph at once:

| Because the graph comes from request metrics… | …this follows |
| --- | --- |
| metrics are produced by **proxies** | a workload with no sidecar is invisible, however busy |
| metrics are **request**-scoped | non-HTTP/TCP traffic appears differently, or not at all |
| rates are over a **window** | an edge fades and disappears after traffic stops |
| labels identify **workloads and services** | a call the metrics cannot attribute is drawn to "unknown" |

## Traffic first, always

Because of row three, the first move when something looks missing is to generate traffic rather than to investigate the graph.

> [!TIP]
> **Try it — generating steady load, and seeing one future edge**
>
> This starts a background loop inside the `tester` pod. It runs until the last checkpoint of [Part 3](./course-03-validations-and-cross-checking.md) stops it.
>
> ```sh
> kubectl -n kiali-demo exec deploy/tester -- sh -c \
>   'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.2; done" >/dev/null 2>&1 &'
> sleep 20
> kubectl -n kiali-demo exec deploy/tester -c istio-proxy -- \
>   pilot-agent request GET stats/prometheus \
>   | grep 'istio_requests_total' | grep 'destination_service_name="notification-service"' | head -2
> ```
>
> Expect something like:
>
> ```text
> istio_requests_total{reporter="source",source_workload="tester",destination_workload="notification-service-v1",response_code="200",...} 98
> ```
>
> That single line is one edge of the graph, before Kiali has drawn anything: a source workload, a destination workload, a response code, a count. Five requests a second is plenty — the graph needs **continuity**, not volume, because it is rendering a rate rather than a total.
>
> Note this came from the proxy directly, not from Prometheus. The proxy is the origin; Prometheus scrapes it roughly every 15 seconds, and Kiali queries Prometheus. Each hop adds delay, which is why a just-started load takes a moment to appear in the UI.

## The pipeline, and where it breaks

```text
   proxy :15090  ──scrape (~15s)──▶  Prometheus  ──query──▶  Kiali  ──▶  your browser
        │                                 │                     │
        │                                 │                     └─ wrong Prometheus URL
        │                                 │                        → empty graph, no error
        │                                 └─ retention / scrape config
        │                                    → graph empty beyond a time range
        └─ no sidecar → no metrics at all
           → workload invisible everywhere downstream
```

Diagnosing an empty graph is a walk along that pipeline, and it is worth doing in order because each stage rules out the ones before it:

1. **Is there traffic?** Send some.
2. **Does the proxy have the metric?** `pilot-agent request GET stats/prometheus | grep istio_requests_total` — as above.
3. **Does Prometheus have it?** Query it directly (the technique in [module 060-02](../../section-060/module-02/course.md)).
4. **Does Kiali reach Prometheus?** Its own configuration and logs.

Stopping at step 1 solves most cases, and step 2 distinguishes "not in the mesh" from "monitoring problem" in one command.

## Reaching the UI

```sh
kubectl -n istio-system port-forward svc/kiali 20001:20001
```

Then open `http://localhost:20001` in a browser that can reach this machine. `istioctl dashboard kiali` does the same thing and additionally tries to launch a browser — convenient locally, and of no use on a headless machine.

The addon install used here runs Kiali with anonymous authentication, which is appropriate for a throwaway playground and not for anything else. A real deployment uses token or OpenID authentication, because Kiali can read every Istio object in the cluster.

> [!WARNING]
> **Pitfalls in the model**
>
> - **Expecting Kiali to work without Prometheus.** It is not a data source. Without metrics the graph is empty and the failure is quiet.
> - **Assuming a `Running` Kiali can reach Prometheus.** A wrong URL in its configuration fails exactly as silently as a missing Prometheus.
> - **Concluding a service is missing from the mesh because it is missing from the graph.** No traffic in the window means no edge. Generate load first.
> - **Forgetting the scrape delay.** Proxy, then Prometheus, then Kiali — a new edge takes tens of seconds to appear even when everything works.
> - **Leaving anonymous authentication enabled outside a playground.** Kiali reads the whole mesh's configuration.

> *Kiali draws a PromQL query with arrows — which is why every limitation of the graph is a property of the metrics underneath it.*

## Reference

- [Kiali documentation](https://kiali.io/docs/) — architecture, configuration, and the Prometheus and Grafana integrations.
- [Istio standard metrics](https://istio.io/latest/docs/reference/config/metrics/) — the labels on `istio_requests_total` that become nodes, edges and badges.
- [Visualizing your mesh](https://istio.io/latest/docs/tasks/observability/kiali/) — Istio's own Kiali task, including installing the addon.
- `kubectl -n istio-system get configmap kiali -o yaml` — Kiali's own configuration on your cluster, including the Prometheus URL it queries.
