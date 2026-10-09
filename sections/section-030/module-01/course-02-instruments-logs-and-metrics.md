# The Instruments

Astronaut, mission control (`istiod`) can fail in four different ways, and each way leaves its own trail. This part gives you the three instruments that read that trail: the pod's own status, the log, and the metrics. Each one answers a different question. Knowing which is which stops you from saying "it is up" based on evidence that only shows the process is alive.

## Readiness is not health

`istiod` answers health checks (probes) on port **15021**. Kubernetes uses them for two different decisions:

- **Liveness**: is the process alive? If this check fails, Kubernetes restarts the container.
- **Readiness**: should this pod get traffic? If this check fails, Kubernetes removes the pod from the `istiod` Service, so webhook calls and new proxy connections go elsewhere.

Both checks are shallow on purpose. They ask "is the server answering?", not "is it keeping the mesh up to date?". A control plane can show `1/1 Ready` while its pushes fail, while it is about to run out of memory, or while it rejects every configuration you give it.

So the field that tells you the most for the least effort is **`RESTARTS`**. The case to recognise is a restart count that keeps climbing on a pod that says `Running`. That is a crash loop that Kubernetes keeps hiding by restarting the pod. It is almost always the memory limit, and every restart makes all proxies reconnect.

<!-- astrona:playground:renew -->

### Read why istiod last stopped

Ask Kubernetes why the `istiod` container last ended:

```sh
kubectl -n istio-system get pod -l app=istiod \
  -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
```

If the container has never ended, there is no last state to print. If it prints `OOMKilled` (killed for running out of memory), that one word is the complete diagnosis.

## What a healthy log says

`istiod`'s log mostly tells the story of its pushes: mission control radioing new orders to the ships. Once you know what normal looks like, the abnormal line stands out.

### Read what istiod says about itself

Read the last 30 lines of the `istiod` log:

```sh
kubectl -n istio-system logs deploy/istiod --tail=30
```

You should see something like:

```text
info    ads     Push debounce stable[3] 1 for config Service/cphealth-demo/notification-service: 100.4ms since last change
info    ads     XDS: Pushing Services:24 ConnectedEndpoints:3 Version:2024-...
info    ads     Incremental push, service notification-service.cphealth-demo.svc.cluster.local
```

The `ads` scope is the Aggregated Discovery Service: the single stream that carries every kind of order. `Push debounce` means `istiod` waits a moment to collect quick changes before it pushes, so ten fast `kubectl apply` commands cause one push, not ten. `ConnectedEndpoints:3` is the number of proxies connected to *this* `istiod` pod.

### What to look for

Scan the log for these patterns, in order of how much each one tells you:

| Pattern | What it means |
| --- | --- |
| `reject` | A proxy refused configuration, or `istiod` refused to build it |
| `error` / `warn` | Anything from a failed watch on the API server to an invalid object |
| Push debounce times climbing into seconds | The control plane is struggling to keep up |
| `ConnectedEndpoints` far below your number of proxies | Proxies are connected to another `istiod` pod, or failing to connect |

## The metrics endpoint

`istiod` publishes metrics in the Prometheus format on port **15014**. You can read them with no monitoring system at all, by asking the pod directly. That matters, because the moment you need these numbers is often the moment your monitoring is unhappy too.

### Decode the metric names

The names look cryptic until you take one apart. Take `pilot_xds_pushes`:

| Piece | Meaning |
| --- | --- |
| `pilot` | The component: "Pilot" is `istiod`'s original name, from when the xDS server was a separate program |
| `xds` | The protocol family: the x Discovery Services |
| `pushes` | What is counted |

Every metric is *component*, then *subsystem*, then *thing counted*. Once you can read one, you can read all of them. These four describe the xDS job:

| Metric | Type | What it says |
| --- | --- | --- |
| `pilot_xds_pushes` | Counter, by `type` (`cds`, `lds`, `eds`, `rds`) | Configuration pushes sent. It should climb when you change something and stay still when you do not. |
| `pilot_xds_push_errors` | Counter | Pushes that failed on the way: connection problems or a lack of resources, not your YAML. |
| `pilot_total_xds_rejects` | Counter | Configuration a **proxy** refused. This is a NACK: the officer radioed back "orders rejected, keeping the old ones". |
| `pilot_proxy_convergence_time` | Histogram | How long a change takes to reach every proxy. The first number to get worse under load. |

Two more are worth knowing by name. `pilot_xds` counts the connected proxies right now (a gauge). `pilot_k8s_cfg_events` counts Kubernetes objects flowing in. Together they tell you whether `istiod` gets input and has an audience for its output.

### Read the push counters on a quiet mesh

Ask `istiod` for its push counters:

```sh
kubectl -n istio-system exec deploy/istiod -- \
  curl -s localhost:15014/metrics | grep -E '^pilot_(xds_pushes|xds_push_errors|total_xds_rejects)' | head
```

You should see something like:

```text
pilot_xds_pushes{type="cds"} 42
pilot_xds_pushes{type="eds"} 57
pilot_xds_pushes{type="lds"} 41
pilot_xds_pushes{type="rds"} 39
```

Notice which metrics are **missing**: `pilot_xds_push_errors` and `pilot_total_xds_rejects` do not appear. The command is not broken. A Prometheus counter is usually not shown at all until it has gone up at least once, so a missing line is the healthy case. Read "no line" as "zero", not as "cannot tell".

## Counters only go up

Every metric above, except the histogram and the gauge, is a **counter**. A counter only goes up, for as long as the process runs. That changes how you read it:

- **The number on its own means nothing.** `pilot_xds_pushes{type="cds"} 42` tells you about uptime, not health.
- **The useful reading is a difference.** Read the value, make a change, read it again. A push that did not happen is your finding.
- **A restart resets every counter to zero.** A counter that is suddenly small is evidence of a restart, which brings you back to the `RESTARTS` field.

A monitoring system such as Prometheus does this subtraction for you, with its `rate()` function. At a terminal, you do it by reading twice.

> [!TIP]
> To check whether a change reached mission control, read `pilot_xds_pushes` before and after the change. No increase means no push.

## Resource pressure: the slow version of an outage

The dramatic failure is `istiod` being gone. The common failure on a real cluster is `istiod` being **slow**: running, ready, pushing, and taking twenty seconds to do what used to take one.

Every symptom is a milder version of the outage. Configuration changes "did not work", then later did. Pods take a long time to become ready. Problems get reported and then disappear before anyone looks.

### Read the instruments for pressure

The same instruments tell this story, read a different way:

| Signal | Where | What it means |
| --- | --- | --- |
| `pilot_proxy_convergence_time` climbing | Metrics | Pushes take longer to reach the fleet |
| Push debounce times in seconds | Log | Changes queue up before a push even starts |
| Memory near the limit | `kubectl top pod -n istio-system` | The next big change may kill it for lack of memory |
| `RESTARTS` going up with no deploys | Pod status | It has already happened |

`istiod`'s memory use grows with the amount of configuration and the number of connected proxies, not with request traffic. So pressure arrives when the cluster grows, which is rarely when anyone is watching.

`kubectl top` needs metrics-server, which a plain `kind` cluster does not install. If it is not available, the restart count and the last termination reason still tell most of the story.

## Common pitfalls

> [!WARNING]
> - **Treating `1/1 Ready` as healthy.** The probes ask "is the server answering?". A ready `istiod` can still reject every push.
> - **Ignoring the restart count on a `Running` pod.** `1/1 Running` with `RESTARTS 14` is a crash loop, and the whole mesh reconnects every few minutes.
> - **Reading counters as absolute values.** Compare before and after a change; a large number only means a long uptime.
> - **Assuming a missing metric means "unknown".** Counters that have never gone up are usually missing completely. No `pilot_total_xds_rejects` line is good news.
> - **Reading only one `istiod` replica's metrics.** Each replica counts its own pushes and its own proxies; `kubectl exec deploy/istiod` reaches exactly one of them.

> *Readiness says the process answered; the counters say whether anything is actually reaching the ships.*
