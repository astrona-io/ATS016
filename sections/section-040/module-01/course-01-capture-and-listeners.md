# Part 1 — Capture And Listeners

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — Routes](./course-02-routes.md).

Before any of Istio's routing applies, something has to make your application's traffic go through Envoy at all. Your code connects to `notification-service:80` exactly as it did before the mesh existed. This part is the mechanism that intercepts it, and the first of the four stages that acts on the result.

## Capture: iptables in the pod's network namespace

[Module 030-03 Part 1](../../section-030/module-03/course-01-the-injection-webhook.md) mentioned that an init container installs `iptables` rules. Those rules are the capture mechanism, and they operate entirely inside the pod's own network namespace — which both containers share.

```text
   pod network namespace
   ┌───────────────────────────────────────────────────────────┐
   │                                                           │
   │   app ──connect() to 10.96.44.31:80──┐                    │
   │                                      │ iptables OUTPUT    │
   │                                      │ REDIRECT           │
   │                                      ▼                    │
   │                            envoy :15001  (outbound)       │
   │                                      │                    │
   │                                      └──▶ out to the pod IP
   │                                                           │
   │   inbound traffic ──┐                                     │
   │                     │ iptables PREROUTING REDIRECT        │
   │                     ▼                                     │
   │           envoy :15006  (inbound) ──▶ app :8084           │
   └───────────────────────────────────────────────────────────┘
```

Three consequences worth carrying:

- **The application is unmodified and unaware.** It dialled a Service IP; the connection was redirected before it left the namespace. No library, no proxy environment variable, no code change.
- **The original destination survives the redirect.** The kernel records it, and Envoy recovers it — which is how a single listener on 15006 can serve many application ports, and why the `ORIGINAL_DST` cluster type in [Part 3](./course-03-clusters-and-endpoints.md) exists.
- **Traffic that bypasses the redirect bypasses the mesh.** Rules can exclude ports or CIDRs (via annotations such as `traffic.sidecar.istio.io/excludeOutboundPorts`), and anything excluded gets no routing, no policy and no telemetry. That is a legitimate tool and an easy way to produce a workload that is "in the mesh" for some traffic only.

## The ports you will see

| Port | Direction | Purpose |
| --- | --- | --- |
| **15001** | outbound | the catch-all: everything the application sends leaves through here |
| **15006** | inbound | the catch-all: everything arriving for the application enters here |
| 15000 | — | Envoy's admin interface, localhost only ([module 010-02 Part 2](../../section-010/module-02/course-02-envoy-log-scopes-at-runtime.md)) |
| 15020 / 15021 | — | health and readiness endpoints, merged application and proxy probes |
| 15090 | — | Prometheus metrics, scraped from outside ([module 060-02](../../section-060/module-02/course.md)) |
| 15012 | outbound | the xDS and certificate stream to `istiod` ([module 030-02](../../section-030/module-02/course-01-xds-and-acknowledgement.md)) |

The four in the middle are infrastructure and never appear in a request path. The two in bold are where this module starts.

## What a listener is

A **listener** is a socket Envoy accepts connections on, plus the chain of filters it applies to what arrives. In a sidecar, listeners are not your application's ports — the application still owns those. They are Istio's own, created to receive redirected traffic.

Alongside the two catch-alls you will see **per-service outbound listeners**, one for each port the proxy knows a destination on. That is a deliberate design: a listener bound to `0.0.0.0:80` with knowledge of which services live on port 80 can hand off to HTTP-aware routing, whereas the 15001 catch-all can only pass bytes along.

> [!TIP]
> **Try it — the ports this proxy is listening on**
>
> ```sh
> istioctl proxy-config listener deploy/tester -n proxycfg-demo | head
> ```
>
> Expect something like:
>
> ```text
> ADDRESSES     PORT  MATCH                                                             DESTINATION
> 10.96.0.10    53    ALL                                                               Cluster: outbound|53||kube-dns.kube-system.svc.cluster.local
> 0.0.0.0       80    Trans: raw_buffer; App: http/1.1,h2c                              Route: 80
> 0.0.0.0       80    ALL                                                               PassthroughCluster
> 0.0.0.0       15001 ALL                                                               PassthroughCluster
> 0.0.0.0       15006 Addr: *:15006                                                     Inline Route: /*
> ```
>
> Read the `DESTINATION` column: it says what happens next, and it is the hand-off from stage one to stage two. The `0.0.0.0:80` line with `App: http/1.1,h2c` hands off to `Route: 80` — that name is what [Part 2](./course-02-routes.md) queries. The `kube-dns` line hands straight to a cluster, skipping routing entirely, because DNS over UDP has no HTTP layer to route on.

## Two listeners on port 80, and why

The output above has **two** entries for `0.0.0.0:80`, with different `MATCH` values. That is not a duplicate. Envoy selects among **filter chains** on one listener using match criteria, and Istio installs two:

```text
   connection arrives on :80
        │
        ├── does it look like HTTP/1.1 or h2c?   ── yes ──▶ HTTP filter chain ──▶ Route: 80
        │                                                    (full routing, headers, retries)
        │
        └── anything else                        ─────────▶ PassthroughCluster
                                                             (bytes forwarded, no routing)
```

The `MATCH` column is the criterion. `Trans: raw_buffer; App: http/1.1,h2c` means "plaintext transport, and the application protocol was detected as HTTP" — Istio sniffs the first bytes of the connection when a port's protocol has not been declared.

This is where the protocol-naming rule from [module 010-02](../../section-010/module-02/course-01-what-describe-resolves.md) becomes concrete. A Service port named `http` tells Istio the protocol in advance and the HTTP chain is used with confidence. A port named `web` leaves it to sniffing, which works for plain HTTP and fails for anything that does not announce itself in the first bytes — server-first protocols such as MySQL, and TLS traffic Istio is not terminating. Those fall to the passthrough chain, and every routing rule you wrote silently stops applying.

## PassthroughCluster is not an error

`PassthroughCluster` appears twice above, and it is the mesh's default for traffic it has no configuration for: forward the bytes to the original destination, unchanged, without routing or policy. Its counterpart `BlackHoleCluster` drops such traffic instead.

Which one you get is the mesh-wide `outboundTrafficPolicy.mode` setting — `ALLOW_ANY` (passthrough, the default) or `REGISTRY_ONLY` (black hole). It matters for diagnosis:

| Mode | Unknown destination | Symptom |
| --- | --- | --- |
| `ALLOW_ANY` | forwarded as-is | calls to external hosts "just work" with no telemetry and no policy |
| `REGISTRY_ONLY` | dropped | calls to anything without a `ServiceEntry` fail, often with a confusing `502` |

If you see traffic reaching an external endpoint that no `ServiceEntry` describes, `PassthroughCluster` is the explanation, and the absence of metrics for it is the consequence.

## Filtering, and reading only what you need

An unfiltered listener dump on a real cluster is hundreds of lines, because a sidecar knows about every Service in the mesh by default. Two flags make the command usable:

- `--port <n>` — only listeners on that port.
- `--address <ip>` — only listeners bound to that address.

Narrowing from the start is the habit; `head` is not a substitute, because the line you want is rarely in the first ten.

> [!TIP]
> **Try it — one port, and what it hands off to**
>
> ```sh
> istioctl proxy-config listener deploy/tester -n proxycfg-demo --port 80
> istioctl proxy-config listener deploy/notification-service-v1 -n proxycfg-demo --port 15006
> ```
>
> Expect something like:
>
> ```text
> ADDRESSES  PORT  MATCH                                     DESTINATION
> 0.0.0.0    80    Trans: raw_buffer; App: http/1.1,h2c      Route: 80
> 0.0.0.0    80    ALL                                       PassthroughCluster
>
> ADDRESSES  PORT   MATCH                                    DESTINATION
> 0.0.0.0    15006  Addr: *:8084                             Cluster: inbound|8084||
> ```
>
> The same command against two workloads shows the two directions. `tester`'s port-80 listener is **outbound** — it is a client, so it has a listener for a destination it might call. `notification-service-v1`'s 15006 listener is **inbound**, matching on the original destination port `8084` and handing to a cluster rather than a route. [Part 4](./course-04-inbound-secrets-and-method.md) takes that direction apart.

## What a missing listener means

Stage one failing has a distinct signature, and it is the one people least expect: traffic that **works but is not in the mesh**, or a connection that is refused outright.

- **No listener for a port, `ALLOW_ANY`** → traffic passes through. Routing rules do not apply, metrics are absent, mTLS is not used. Everything looks fine until someone asks why the dashboards are empty.
- **No listener for a port, `REGISTRY_ONLY`** → traffic is dropped. Usually a missing `ServiceEntry` for an external host.
- **No inbound listener on the destination** → the receiving proxy has nothing to hand to the application; server-side policy cannot apply.

So the question this stage answers is not "did routing work" but "was this traffic ever Istio's to route".

> [!WARNING]
> **Pitfalls at the capture and listener stage**
>
> - **Looking for your application's ports in the listener list.** The listeners are Istio's — 15001, 15006, and per-destination outbound listeners. The application's own port appears as a `MATCH` criterion on 15006, not as a listener of its own.
> - **Treating `PassthroughCluster` as a fault.** It is the default for unknown destinations. It is only a problem when you expected configuration to apply.
> - **Relying on protocol sniffing.** Name the Service port (`http`, `grpc`, `tcp`, …) or set `appProtocol`. Sniffing fails silently for server-first protocols and sends them down the passthrough chain.
> - **Forgetting traffic exclusions.** `excludeOutboundPorts` and friends remove traffic from the mesh entirely — no routing, no policy, no telemetry — and nothing in the listener list hints that a port was excluded.
> - **Dumping listeners unfiltered on a real cluster.** Use `--port` or `--address`; the default output is a sidecar's entire view of the mesh.

> *Stage one does not ask where a request should go — it asks whether the mesh ever saw it.*

## Reference

- [Traffic capture and the sidecar](https://istio.io/latest/docs/ops/configuration/traffic-management/traffic-routing/) — how redirection and the catch-all listeners fit together.
- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — port naming, `appProtocol`, and exactly which protocols sniffing can and cannot detect.
- [Envoy listeners](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/listeners/listeners) — filter chains and chain matching, the mechanism behind the two port-80 entries.
- [outboundTrafficPolicy](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-control/) — `ALLOW_ANY` against `REGISTRY_ONLY`, and what each does to unknown destinations.
