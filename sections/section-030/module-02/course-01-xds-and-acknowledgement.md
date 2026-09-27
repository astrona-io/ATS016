# Part 1 — How Configuration Reaches A Proxy

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — Reading The Table](./course-02-reading-the-proxy-status-table.md).

`istioctl proxy-status` can report whether a proxy accepted its configuration only because the protocol carrying that configuration is acknowledged. This part is that protocol: who connects to whom, what travels, and what comes back.

## Envoy does not read Kubernetes

A sidecar has no Kubernetes client, no watch on the API server and no idea what a `VirtualService` is. It receives its entire configuration over a **gRPC stream** from `istiod`, using a protocol family called **xDS** — the **x** **D**iscovery **S**ervices, where the `x` stands for whichever kind of resource is being discovered.

```text
   pod
   ┌──────────────────────────────┐
   │  app container               │
   │                              │
   │  istio-proxy                 │
   │   ├── pilot-agent ───────────┼──── gRPC, outbound ────▶ istiod.istio-system.svc:15012
   │   │     (holds the stream,   │                          (mTLS, ServiceAccount identity)
   │   │      also fetches certs) │
   │   └── envoy ◀── local xDS ───┤
   │         (localhost:15000 admin)
   └──────────────────────────────┘
```

Three properties of that picture matter for everything downstream:

- **The proxy dials out.** `istiod` never connects to a pod. A proxy that cannot reach `istiod.istio-system.svc:15012` simply has no stream — and, as [Part 3](./course-03-absence-and-per-proxy-diff.md) shows, no row.
- **The stream is long-lived.** It is not a poll. Configuration is pushed when it changes, and the connection stays open in between.
- **`pilot-agent` sits in the middle.** It authenticates with the pod's ServiceAccount token, obtains the workload certificate, and proxies xDS to Envoy locally. That is why a certificate problem and a configuration problem can look alike: they travel the same connection.

## The four resource types

xDS is a family, one member per kind of resource. Four appear constantly, and they are the four columns of the command this module is about:

| Type | Expands to | Carries |
| --- | --- | --- |
| `CDS` | Cluster Discovery Service | the **clusters** — named groups of upstream endpoints, roughly "a Service, or one subset of one" |
| `LDS` | Listener Discovery Service | the **listeners** — one per port the proxy accepts traffic on |
| `EDS` | Endpoint Discovery Service | the **endpoints** — the actual pod IPs behind each cluster |
| `RDS` | Route Discovery Service | the **routes** — which request goes to which cluster |

They compose in a fixed order, and it is the same chain [section 040](../../section-040/module-01/course.md) walks by hand:

```text
   LDS  a listener accepts the connection on a port
     │
     ▼
   RDS  a route matches the request and names a cluster
     │
     ▼
   CDS  the cluster describes how to talk to that upstream
     │
     ▼
   EDS  the endpoints are the addresses it resolves to
```

You will also see **`ECDS`** (Extension Config Discovery Service) in modern output — configuration for WebAssembly and similar extensions. In a mesh with no extensions it has nothing to carry, which is why it sits permanently at `NOT SENT`.

Istio delivers all of these over a single multiplexed stream called **ADS** (Aggregated Discovery Service). That is not a trivia detail: ordering matters when configuration changes — a route referring to a cluster that has not arrived yet would be invalid — and one ordered stream is how that is avoided.

## The exchange that makes state knowable

Each type is versioned and each push must be answered. The exchange, simplified:

```text
   istiod ──▶ DiscoveryResponse   { type: CDS, version_info: "2024-...", nonce: "abc" }
                                    (the resources)
   proxy  ──▶ DiscoveryRequest    { type: CDS, version_info: "2024-...", response_nonce: "abc" }
                                    → ACK: accepted, now at this version
       or
   proxy  ──▶ DiscoveryRequest    { type: CDS, version_info: <previous>, response_nonce: "abc",
                                    error_detail: { message: "..." } }
                                    → NACK: rejected, staying on the old version
```

Read the difference carefully, because it explains a surprising failure mode. An **ACK** echoes the new version. A **NACK** echoes the *previous* version plus an error. A proxy that NACKs does not fall back to nothing — **it keeps running the last configuration it accepted**. Your change is refused and the mesh keeps working on stale rules, which is precisely the "I applied it and nothing happened" report from [module 030-01 Part 3](../module-01/course-03-outage-anatomy-and-rejects.md).

On the control plane side, a NACK increments `pilot_total_xds_rejects` and writes a line to the `istiod` log. On the proxy side, it appears in the `istio-proxy` container log. Neither is surfaced by `kubectl`.

From this bookkeeping the three states fall out directly, and [Part 2](./course-02-reading-the-proxy-status-table.md) names them:

| `istiod`'s record | Table shows |
| --- | --- |
| sent version X, received ACK for X | `SYNCED` |
| sent version X, no answer yet — or a NACK | `STALE` |
| nothing to send for this type | `NOT SENT` |

## Seeing the connection from the proxy's side

The proxy logs the stream it holds. On a healthy sidecar this is one quiet line, and knowing its shape is what makes the failing version recognisable.

> [!TIP]
> **Try it — what a proxy says about its control plane connection**
>
> ```sh
> kubectl -n proxysync-demo logs deploy/notification-service-v1 -c istio-proxy --tail=40 \
>   | grep -i -E 'xds|15012|connect'
> ```
>
> Expect something like:
>
> ```text
> info    sds     resource:default new connection
> info    xdsproxy connected to delta upstream XDS server: istiod.istio-system.svc:15012
> ```
>
> Two subsystems on one connection: `sds` is the Secret Discovery Service delivering this workload's certificate, and `xdsproxy` is `pilot-agent` relaying configuration to Envoy. The word **`delta`** names the variant in use — delta xDS sends only what changed rather than the full resource set on every update, which is what keeps a large mesh affordable.
>
> On a proxy that cannot reach `istiod`, the same grep produces a repeating loop of `connection refused` or `context deadline exceeded` against `istiod.istio-system.svc:15012` — naming both the destination and the port to unblock.

## Why this is worth knowing before reading the table

Three practical consequences, each of which is a mistake avoided later:

- **`SYNCED` is a statement about a protocol exchange, not about correctness.** It means the bytes were accepted. Configuration that is wrong synchronises perfectly.
- **A NACKed change leaves the proxy on old, working configuration.** Nothing breaks; nothing updates. Look for the reject, not for an outage.
- **No stream means no row.** There is no "disconnected" state to display, because the table is built from the connections `istiod` currently holds.

> *xDS is a push over an acknowledged stream — and it is the acknowledgement, not the push, that proxy-status reports.*

## Reference

- [xDS protocol](https://www.envoyproxy.io/docs/envoy/latest/api-docs/xds_protocol) — the ACK/NACK exchange, version/nonce semantics, and why delta xDS exists. The authoritative source for this part.
- [Istio architecture — Envoy and istiod](https://istio.io/latest/docs/ops/deployment/architecture/) — where port 15012 and the agent fit.
- [Istio identity and SDS](https://istio.io/latest/docs/concepts/security/#istio-identity) — the certificate half of the same connection.
- `kubectl -n proxysync-demo logs deploy/tester -c istio-proxy` — your own proxy's startup sequence; worth reading in full once.
