# Part 1 — Four Jobs In One Process

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — The Instruments](./course-02-instruments-logs-and-metrics.md).

`istiod` is one binary and one Deployment, which makes it tempting to treat as a single thing that is either up or down. It is more useful — and far more diagnostic — to treat it as four services that happen to share a process, because they fail independently and each failure has a different signature.

## The four jobs

```text
                        ┌──────────────────── istiod ────────────────────┐
   Kubernetes API  ────▶│                                                │
   (watch: Services,    │  1. xDS SERVER         ──gRPC:15012──▶ proxies │
    Pods, Istio CRs)    │     translate config into Envoy resources      │
                        │                                                │
                        │  2. CERTIFICATE AUTHORITY ──15012──▶ proxies   │
                        │     sign workload certs (CSR over the same     │
                        │     port, authenticated by ServiceAccount)     │
                        │                                                │
   API server ─────────▶│  3. INJECTION WEBHOOK   (mutating, :15017)     │
   (admission)          │     add istio-proxy to new pods                │
                        │                                                │
   API server ─────────▶│  4. VALIDATION WEBHOOK  (validating, :15017)   │
   (admission)          │     reject invalid Istio resources             │
                        └────────────────────────────────────────────────┘
```

Note which direction each arrow points. Jobs 1 and 2 are **pull** — proxies connect outward to `istiod` and hold a long-lived stream. Jobs 3 and 4 are **push** — the API server calls `istiod` synchronously, on the critical path of a write.

That asymmetry is the whole reason the failures look so different. A proxy that cannot reach `istiod` keeps what it has and carries on. An API server that cannot reach `istiod` has a decision to make about a request that is waiting.

## How each failure presents

| Job | What it does | How the mesh degrades without it |
| --- | --- | --- |
| **xDS config server** | Pushes routing, policy and endpoints to every proxy | Running proxies keep their last configuration and serve traffic normally. No configuration change takes effect. New pods never become ready. |
| **Certificate authority** | Issues and rotates workload certificates | Nothing immediately. Certificates are typically valid for around 24 hours, so a long outage eventually breaks mTLS everywhere at once. |
| **Injection webhook** | Adds the sidecar to new pods | Depends on `failurePolicy`: `Fail` (the Istio default) blocks pod creation outright; `Ignore` lets pods start with **no sidecar**, silently outside the mesh. |
| **Validation webhook** | Rejects invalid Istio resources at apply time | Invalid configuration starts being *accepted* by the API server, then refused later when `istiod` tries to push it. |

Read that table backwards, as a diagnostic:

- *"New pods stay unready but existing traffic is fine"* → job 1.
- *"Everything broke at once, about a day after that incident"* → job 2.
- *"Half our pods have no sidecar"* → job 3 with `failurePolicy: Ignore`.
- *"Pods will not schedule, webhook errors in the events"* → job 3 with `failurePolicy: Fail`.
- *"I applied it, it exists, nothing happened"* → job 4, and [Part 3](./course-03-outage-anatomy-and-rejects.md).

## Why traffic survives at all

The single most misleading property of a control plane outage is that the data plane keeps working. Two independent caches are responsible:

**Configuration.** Each proxy holds its complete Envoy configuration in memory. xDS is a streaming protocol — `istiod` sends updates, the proxy acknowledges them and keeps them. When the stream drops, nothing is discarded; the proxy simply stops receiving changes. It will keep routing traffic according to a configuration that may be hours old.

**Identity.** Each proxy holds an issued workload certificate and the mesh root. mTLS handshakes are between proxies, using material they already have. `istiod` signed those certificates and is not consulted again until renewal.

So a mesh with no control plane is a mesh frozen in time: fully functional, completely unable to change.

## The certificate clock

Job 2 is the one that turns a survivable outage into a total one, and it does so on a timer rather than on an event.

Workload certificates are short-lived by design — commonly around 24 hours, configurable. The proxy's agent renews them well before expiry, typically when roughly half the lifetime has elapsed. Renewal requires reaching `istiod`.

```text
  t=0      outage begins.          Traffic normal. Nobody notices.
  t≈12h    first renewals due.     Attempts fail, retried. Existing certs still valid.
  t≈24h    certs expire.           mTLS handshakes fail across the mesh, roughly at once.
```

Two things make this dangerous. First, the failure arrives long after the change that caused it, so the obvious suspect is whatever happened at `t=24h` rather than the control plane that went away yesterday. Second, it arrives *everywhere simultaneously*, because certificates issued around the same time expire around the same time — it does not degrade gracefully, it falls over.

As an analogy: it is a building pass system where the passes expire at midnight. Take the pass office offline in the morning and nothing happens all day; the next morning nobody can get in, all at once. The analogy breaks down in one useful way — unlike a pass, a certificate is also what proves *identity*, so an expired one does not merely deny access, it makes the workload unidentifiable to its peers.

## Establishing a baseline

Before you can call a control plane unhealthy you need to know what healthy looks like here. Three facts, in order: is it ready, how many times has it restarted, and how long has it been up.

> [!TIP]
> **Try it — the control plane's baseline**
>
> ```sh
> kubectl -n istio-system get pods -l app=istiod
> kubectl -n istio-system get deploy istiod \
>   -o jsonpath='{.status.readyReplicas}/{.status.replicas}{"\n"}'
> ```
>
> Expect something like:
>
> ```text
> NAME                      READY   STATUS    RESTARTS   AGE
> istiod-7d4c9b8f4-k2m8x    1/1     Running   0          12m
> 1/1
> ```
>
> `1/1`, `Running`, `RESTARTS 0` is the baseline for this playground. Write down the restart count: on a real cluster it is the number that quietly tells you whether the control plane has been stable, and it is the one field people never check.

A note on replica count. Production installs run `istiod` with more than one replica, and the four jobs behave differently under partial failure: the webhooks are fronted by a Service and survive losing one pod, while each proxy holds a stream to **one** specific `istiod` pod and is redistributed when that pod goes away. A rolling `istiod` restart is therefore a brief reconnect storm rather than an outage — which is also why the `ISTIOD` column in [`proxy-status`](../module-02/course.md) exists.

> [!WARNING]
> **Pitfalls in the mental model**
>
> - **Concluding the control plane is fine because traffic is flowing.** Proxies serve from cached configuration and already-issued certificates. Working traffic proves nothing about `istiod`; try a configuration change or a pod restart instead.
> - **Forgetting the certificate clock.** An outage lasting longer than the workload certificate lifetime breaks mTLS across the mesh simultaneously, long after the incident that caused it.
> - **Treating `istiod` as one thing.** Injection can be broken while xDS is fine, and vice versa. Identify the job before the fix.
> - **Assuming a multi-replica control plane means no single point of failure per proxy.** Each proxy is attached to one `istiod` instance at a time.

> *A mesh without its control plane is frozen, not broken — and the freeze has an expiry date measured in certificate lifetimes.*

## Reference

- [Istio architecture](https://istio.io/latest/docs/ops/deployment/architecture/) — the component diagram this part expands, including the port numbers.
- [Istio security — PKI](https://istio.io/latest/docs/concepts/security/#pki) — certificate issuance and the rotation lifecycle behind the clock above.
- [Deployment models and the control plane](https://istio.io/latest/docs/ops/deployment/deployment-models/) — replica and revision topologies, and what each proxy is attached to.
- `kubectl -n istio-system get deploy istiod -o yaml` — the concrete ports, probes and resource limits on your own install; worth reading once against the diagram.
