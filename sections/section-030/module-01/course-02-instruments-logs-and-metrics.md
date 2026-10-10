# The Instruments

`istiod` can fail in four different ways, and each way leaves its own trail. This part covers the three sources of evidence that read that trail: the pod's own status, the `istiod` log and the `istiod` metrics. Each one answers a different question. Knowing which is which stops you from saying "it is up" based on evidence that only shows the process is alive.

## Readiness is not health

Kubernetes decides whether a pod gets traffic with a readiness probe: a check it runs again and again against the container. `istiod` has one readiness probe, an HTTP request to the path `/ready` on port `8080`. If the probe fails, Kubernetes removes the pod from the `istiod` Service, so webhook calls and new proxy connections go to other replicas. `istiod` has no liveness probe, so Kubernetes restarts the container only when the process itself exits, for example when it crashes or runs out of memory.

The readiness probe is shallow on purpose. It asks "is the server answering?", not "is it keeping the mesh up to date?". A control plane can show `1/1 Ready` while its proxies reject what it sends, while it is about to run out of memory, or while it refuses every object you apply.

So the field that tells you the most for the least effort is **`RESTARTS`**. The case to recognise is a restart count that keeps climbing on a pod that says `Running`. That is a crash loop that Kubernetes keeps hiding by restarting the container. It is most often the memory limit, and every restart makes all proxies reconnect.

<!-- astrona:playground:renew -->

Ask Kubernetes why the `istiod` container last stopped:

```sh
kubectl -n istio-system get pod -l app=istiod \
  -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
```

If the container has never stopped, there is no last state, and the command prints an empty line. If it prints `OOMKilled`, the kernel killed the process because it used more memory than its limit, and that one word is the diagnosis.

## What a healthy log says

The `istiod` log mostly records its pushes: each time it sends new configuration to the proxies. Once you know what normal looks like, an abnormal line stands out. Read the last 30 lines of the log:

```sh
kubectl -n istio-system logs deploy/istiod --tail=30
```

You should see lines like these (shortened to six of the thirty lines):

```text
2026-10-09T22:17:41.418293Z	info	delta	ADS: new delta connection for node:notification-service-v1-54dd46d4b6-flm8c.cphealth-demo-3
2026-10-09T22:17:41.419131Z	info	delta	CDS: PUSH request for node:notification-service-v1-54dd46d4b6-flm8c.cphealth-demo resources:23 removed:0 size:24.2kB cached:0/19
2026-10-09T22:17:41.467504Z	info	delta	LDS: PUSH request for node:notification-service-v1-54dd46d4b6-flm8c.cphealth-demo resources:17 removed:0 size:49.2kB
2026-10-09T22:17:46.174568Z	info	delta	CDS: PUSH for node:tester-69699fd775-96h4j.cphealth-demo resources:22 removed:0 size:23.9kB cached:0/19
2026-10-09T22:17:50.220929Z	info	ads	Push debounce stable[11] 1 for config ServiceEntry/cphealth-demo/notification-service.cphealth-demo.svc.cluster.local: 100.490871ms since last change, 100.49083ms since last push, full=false
2026-10-09T22:17:50.221417Z	info	ads	XDS: Incremental Pushing ConnectedEndpoints:4 Version:2026-10-09T22:17:40Z/7
```

Most lines come from the `delta` scope. Istio 1.30 sends configuration over delta xDS, which sends only the resources that changed, and it logs one line per type and proxy: `CDS: PUSH ... for node:<pod>.<namespace>` means the clusters were pushed to that proxy. A `PUSH request` line answers a proxy that just connected (`ADS: new delta connection`); a plain `PUSH` line is a push that a change caused. The `ads` scope is the Aggregated Discovery Service: the single xDS stream that carries every type of configuration to a proxy. `Push debounce` means `istiod` waits a short time to collect quick changes before it pushes, so ten fast `kubectl apply` commands cause one push, not ten. `ConnectedEndpoints:4` is the number of proxies connected to *this* `istiod` pod: the two pods in `cphealth-demo` plus the ingress and egress gateways that the `demo` profile installs.

Scan the log for these patterns, in order of how much each one tells you:

| Pattern | What it means |
| --- | --- |
| `reject` | A proxy refused configuration, or `istiod` refused an object |
| `error` / `warn` | Anything from a failed watch on the API server to an invalid object |
| Debounce times climbing into seconds | The control plane is struggling to keep up |
| `ConnectedEndpoints` far below your number of proxies | Proxies are connected to another `istiod` pod, or cannot connect |

## The metrics endpoint

The log tells you what happened; the metrics tell you how often. `istiod` publishes metrics in the Prometheus format on port **15014**. You can read them with no monitoring system at all, by asking the pod directly. That matters, because the moment you need these numbers is often the moment your monitoring has problems too.

The names look cryptic until you take one apart. In `pilot_xds_pushes`, `pilot` is the component: Pilot is the original name of the xDS server, from before it was merged into `istiod`. `xds` is the protocol family, and `pushes` is what is counted. Most metrics follow that order: component, then subsystem, then the thing counted. These four describe the xDS job:

| Metric | Type | What it says |
| --- | --- | --- |
| `pilot_xds_pushes` | Counter, by `type` (`cds`, `lds`, `eds`, `rds`) | Configuration pushes sent. It goes up when something changes and stays still when nothing does. |
| `pilot_total_xds_rejects` | Counter | Configuration a **proxy** refused. The proxy sends back a NACK (negative acknowledgement) and keeps its previous configuration. |
| `pilot_total_xds_internal_errors` | Counter | Errors inside `istiod` while it serves xDS, not errors in your YAML. |
| `pilot_proxy_convergence_time` | Histogram | How long a change takes to reach the proxies. The first number to get worse under load. |

Two more are worth knowing by name. `pilot_xds` is a gauge: the number of proxies connected to this `istiod` pod right now. `pilot_k8s_cfg_events` counts the Istio object changes `istiod` receives from the API server. Together they tell you whether `istiod` gets input and has proxies to send output to.

Ask `istiod` for its push and reject counters:

```sh
kubectl -n istio-system exec deploy/istiod -- \
  curl -s localhost:15014/metrics | grep -E '^pilot_(xds_pushes|total_xds_internal_errors|total_xds_rejects)' | head
```

You should see something like:

```text
pilot_xds_pushes{type="cds"} 17
pilot_xds_pushes{type="eds"} 29
pilot_xds_pushes{type="lds"} 17
pilot_xds_pushes{type="rds"} 4
```

Notice which metrics are **missing**: `pilot_total_xds_internal_errors` and `pilot_total_xds_rejects` do not appear. The command is not broken. A counter is usually not shown at all until it has gone up at least once, so a missing line is the healthy case. Read "no line" as "zero", not as "cannot tell".

## Counters only go up

Every metric above, except the histogram and the gauge, is a **counter**. A counter only goes up, for as long as the process runs, and that changes how you read it. The number on its own means little: `pilot_xds_pushes{type="cds"} 17` tells you about uptime, not health. The useful reading is a difference: read the value, make a change, and read it again. A push that did not happen is your finding. A restart resets every counter to zero, so a counter that is suddenly small is evidence of a restart, which brings you back to the `RESTARTS` field.

A monitoring system such as Prometheus does this subtraction for you with its `rate()` function. At a terminal, you do it by reading twice.

> [!TIP]
> To check whether a change reached `istiod`, read `pilot_xds_pushes` before and after the change. No increase means no push.

## Resource pressure: the slow version of an outage

The dramatic failure is `istiod` being gone. The common failure on a real cluster is `istiod` being **slow**: running, ready and pushing, but taking twenty seconds to do what used to take one. Every symptom is a milder version of the outage. Configuration changes "did not work", and later did. Pods take a long time to become ready. Problems get reported and disappear before anyone looks.

The same three sources show this, read a different way:

| Signal | Where | What it means |
| --- | --- | --- |
| `pilot_proxy_convergence_time` climbing | Metrics | Pushes take longer to reach the proxies |
| Debounce times in seconds | Log | Changes queue up before a push even starts |
| Memory near the limit | `kubectl top pod -n istio-system` | The next big change may get it `OOMKilled` |
| `RESTARTS` going up with no deploys | Pod status | It has already happened |

`istiod`'s memory use grows with the amount of configuration and the number of connected proxies, not with request traffic. So pressure arrives when the cluster grows, which is rarely when anyone is watching. `kubectl top` needs metrics-server, which a plain `kind` cluster does not install. Without it, the restart count and the last termination reason still tell most of the story.

You can now read the three sources of evidence about `istiod`: the pod status and its restart count, the log and its push lines, and the counters on port `15014`. You know that a missing counter means zero and that only a difference between two readings means something. What you have not seen yet is how these signals, and the mesh itself, behave when `istiod` is gone.

## Common pitfalls

> [!WARNING]
> - **Treating `1/1 Ready` as healthy.** The readiness probe only asks whether the server answers. A ready `istiod` can still have every push rejected.
> - **Ignoring the restart count on a `Running` pod.** `1/1 Running` with `RESTARTS 14` is a crash loop, and the whole mesh reconnects every few minutes.
> - **Reading counters as absolute values.** Compare before and after a change; a large number only means a long uptime.
> - **Assuming a missing metric means "unknown".** Counters that have never gone up are usually missing completely. No `pilot_total_xds_rejects` line is good news.
> - **Reading only one `istiod` replica's metrics.** Each replica counts its own pushes and its own proxies, and `kubectl exec deploy/istiod` reaches exactly one of them.
