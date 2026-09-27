# Part 2 — The Instruments

> Prerequisite: [Part 1 — Four Jobs In One Process](./course-01-the-four-jobs-of-istiod.md). Next: [Part 3 — Outage Anatomy And Rejected Configuration](./course-03-outage-anatomy-and-rejects.md).

Part 1 gave you four failure signatures. This part gives you the three places to read them from: the pod's own status, the log, and the metrics endpoint. Each answers a different question, and knowing which is which stops you concluding "it is up" from evidence that only shows the process is alive.

## Readiness is not health

`istiod` exposes probes on port **15021**, and Kubernetes uses them for two different decisions:

- **Liveness** — is the process alive? A failure here restarts the container.
- **Readiness** — should this pod receive traffic? A failure here removes it from the `istiod` Service's endpoints, so webhook calls and new proxy connections go elsewhere.

Both are shallow by design. They answer "is the server responding", not "is it converging the mesh". A control plane can be `1/1 Ready` while pushes are failing, while memory is about to be exhausted, or while it is rejecting every configuration you give it.

The field that carries the most information for the least effort is therefore **`RESTARTS`**, and the case to recognise is a climbing restart count on a `Running` pod. That is a crash loop that Kubernetes keeps papering over, almost always the memory limit, and its effect on the mesh is a cycle of convergence and reconnection every few minutes. Pair it with the termination reason to confirm:

```sh
kubectl -n istio-system get pod -l app=istiod \
  -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
```

An `OOMKilled` there is a complete diagnosis.

## What a healthy log says

`istiod`'s log is mostly a narration of pushes. Knowing the normal shape is what makes the abnormal line visible.

> [!TIP]
> **Try it — what istiod is saying about itself**
>
> ```sh
> kubectl -n istio-system logs deploy/istiod --tail=30
> ```
>
> Expect something like:
>
> ```text
> info    ads     Push debounce stable[3] 1 for config Service/cphealth-demo/notification-service: 100.4ms since last change
> info    ads     XDS: Pushing Services:24 ConnectedEndpoints:3 Version:2024-...
> info    ads     Incremental push, service notification-service.cphealth-demo.svc.cluster.local
> ```
>
> The `ads` scope is the Aggregated Discovery Service — the single stream that carries all xDS types. `Push debounce` is `istiod` batching rapid changes before pushing, which is why a burst of `kubectl apply` produces one push rather than ten. `ConnectedEndpoints:3` is the number of proxies attached to *this* instance.

What to scan for, in order of how much it tells you:

| Pattern | Means |
| --- | --- |
| `reject` | a proxy refused configuration, or `istiod` refused to build it — see [Part 3](./course-03-outage-anatomy-and-rejects.md) |
| `error` / `warn` | anything from a failed API watch to an invalid resource |
| a push debounce time climbing into seconds | the control plane is struggling to keep up |
| `ConnectedEndpoints` far below your proxy count | proxies are attached elsewhere, or failing to attach |

## The metrics endpoint

`istiod` serves Prometheus metrics on port **15014**. You can read them with no monitoring stack at all by asking the pod directly, which is worth knowing because the moment you need them is often the moment the monitoring is also unhappy.

The names look cryptic until you decompose them once:

```text
   pilot  _  xds  _  pushes
     │        │        │
     │        │        └── what is counted
     │        └─────────── the protocol family: x Discovery Service
     └──────────────────── the component: "Pilot", istiod's original name
                            (the xDS server used to be a separate binary)
```

Every metric is *component* + *subsystem* + *thing counted*, so once you can read one you can read all of them. The four that describe the xDS job:

| Metric | Type | Says |
| --- | --- | --- |
| `pilot_xds_pushes` | counter, by `type` (`cds`/`lds`/`eds`/`rds`) | configuration pushes sent. Should climb when you change something and sit still when you do not. |
| `pilot_xds_push_errors` | counter | pushes that failed in transit — connectivity or resource pressure, not your YAML. |
| `pilot_total_xds_rejects` | counter | configuration a **proxy** refused (a NACK). Your config arrived and the proxy said no. |
| `pilot_proxy_convergence_time` | histogram | how long a change takes to reach every proxy. The first thing to degrade under load. |

Two more worth knowing by name: `pilot_xds` (the number of connected proxies, as a gauge) and `pilot_k8s_cfg_events` (Kubernetes objects flowing in), which together tell you whether `istiod` is seeing input and has an audience for its output.

> [!TIP]
> **Try it — the push counters on a quiet mesh**
>
> ```sh
> kubectl -n istio-system exec deploy/istiod -- \
>   curl -s localhost:15014/metrics | grep -E '^pilot_(xds_pushes|xds_push_errors|total_xds_rejects)' | head
> ```
>
> Expect something like:
>
> ```text
> pilot_xds_pushes{type="cds"} 42
> pilot_xds_pushes{type="eds"} 57
> pilot_xds_pushes{type="lds"} 41
> pilot_xds_pushes{type="rds"} 39
> ```
>
> Note which metrics are **missing**: `pilot_xds_push_errors` and `pilot_total_xds_rejects` do not appear. That is not an error in the command — a Prometheus counter is generally not emitted until it has been incremented at least once, so absence is the healthy case. Reading "no line" as "cannot tell" rather than "zero" is a mistake that sends people looking for a monitoring problem instead of accepting good news.

## Counters only go up

Every metric above except the histogram and the gauge is a **counter**: monotonically increasing for the lifetime of the process. Three consequences that govern how you read them:

- **The absolute value means nothing.** `pilot_xds_pushes{type="cds"} 42` is a statement about uptime, not health.
- **The useful reading is a difference.** Record the value, make a change, read it again. A push that did not happen is the finding.
- **A restart resets them to zero.** A counter that suddenly looks small is evidence of a restart, which loops back to the `RESTARTS` field above.

In a real setup Prometheus does this differencing for you with `rate()`, which is [module 060-02](../../section-060/module-02/course.md)'s subject. At a terminal, you do it by reading twice.

## Resource pressure: the slow version of an outage

The dramatic failure is `istiod` being absent. The common failure in a real cluster is `istiod` being **slow**: running, ready, pushing — and taking twenty seconds to do what used to take one.

Every symptom is a milder version of the outage. Configuration changes that "did not work" and then did. Pods that take a long time to become ready. Intermittent reports that resolve themselves before anyone looks.

The instruments, read differently:

| Signal | Where | Means |
| --- | --- | --- |
| `pilot_proxy_convergence_time` climbing | metrics | pushes are taking longer to land across the fleet |
| push debounce times in seconds | log | changes are queueing before a push even starts |
| memory near the limit | `kubectl top pod -n istio-system` | the next big change may OOM it |
| `RESTARTS` increasing with no deploys | pod status | it already has |

`istiod`'s memory footprint scales with the size of the configuration set and the number of connected proxies, not with request volume — so pressure arrives when the cluster grows, which is rarely when anyone is watching it.

Note that `kubectl top` needs metrics-server, which a plain `kind` cluster does not install. If it is unavailable, the restart count and last termination reason still carry most of the story.

> [!WARNING]
> **Pitfalls in reading the instruments**
>
> - **Treating `1/1 Ready` as healthy.** The probes answer "is the server responding". A ready `istiod` can be rejecting every push.
> - **Ignoring restart count on a `Running` pod.** `1/1 Running` with `RESTARTS 14` is a crash loop, and the mesh is reconverging every few minutes.
> - **Reading counter metrics as absolute values.** Compare before and after a change; a large number is just uptime.
> - **Assuming a missing metric means zero.** Counters that have never incremented are usually absent entirely. `pilot_total_xds_rejects` not appearing is good news.
> - **Looking only at one `istiod` replica's metrics.** Each instance counts its own pushes and its own connected proxies; `kubectl exec deploy/istiod` reaches exactly one of them.

> *Readiness says the process answered; the counters say whether anything is actually converging.*

## Reference

- [Istio standard metrics — control plane](https://istio.io/latest/docs/reference/config/metrics/) — the published metric list, including the ones this part names.
- [Observing the control plane](https://istio.io/latest/docs/ops/diagnostic-tools/controlz/) — `istioctl dashboard controlz`, a live view of `istiod`'s internal scopes and logging levels.
- `kubectl -n istio-system exec deploy/istiod -- curl -s localhost:15014/metrics | grep '^# HELP pilot'` — the self-documenting form; every metric on your own version with its own description.
- [Prometheus metric types](https://prometheus.io/docs/concepts/metric_types/) — counters, gauges and histograms, if "absence is not zero" was new.
