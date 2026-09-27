# Part 3 — Clusters And Endpoints

> Prerequisite: [Part 2 — Routes](./course-02-routes.md). Next: [Part 4 — The Inbound Direction, Certificates And Method](./course-04-inbound-secrets-and-method.md).

Stage two produced a name. This part is about what that name refers to, how Istio constructs it, and what happens when it refers to nothing — which is the most common failure in an Istio mesh and the subject of [module 040-02](../module-02/course.md).

## What a cluster is

In Envoy's vocabulary a **cluster** is a named group of upstream hosts plus the policy for talking to them: load balancing algorithm, connection pool limits, outlier detection, TLS settings, timeouts. It is the object your `DestinationRule` configures.

Importantly, a cluster is a *definition*, not a list of addresses. The addresses are stage four, discovered separately and updated independently. That separation is what lets a pod roll without touching routing: the cluster is unchanged, its endpoints are replaced.

## Reading the name

Istio names clusters with a four-field convention, and the name alone tells you where a problem is:

```text
outbound | 80 | v1 | notification-service.proxycfg-demo.svc.cluster.local
   │       │     │                      │
   │       │     │                      └─ the destination's fully qualified name
   │       │     └──────────────────────── the subset, from a DestinationRule; EMPTY means "no subset"
   │       └────────────────────────────── the port (the SERVICE port, not the container port)
   └────────────────────────────────────── direction: outbound (leaving this pod) or inbound (arriving)
```

Two consequences follow immediately and both matter in practice:

- **`outbound|80||notification-service...`** — with an empty third field — is the subsetless cluster. It always exists for a Service the proxy knows about, whether or not any `DestinationRule` exists.
- **`outbound|80|v3|notification-service...`** exists **only** if a `DestinationRule` defines a subset named `v3`. A route naming a subset with no cluster behind it is the single most common cause of a `503` in Istio.

So the third field is where `DestinationRule` and `VirtualService` meet. The `VirtualService` writes a subset name into a route; the `DestinationRule` is what makes a cluster of that name exist. Nothing checks that the two agree at admission time ([module 010-01 Part 1](../../section-010/module-01/course-01-admission-and-the-analysis-gap.md)).

> [!TIP]
> **Try it — the clusters for one destination**
>
> ```sh
> istioctl proxy-config cluster deploy/tester -n proxycfg-demo \
>   --fqdn notification-service.proxycfg-demo.svc.cluster.local
> ```
>
> Expect something like:
>
> ```text
> SERVICE FQDN                                              PORT  SUBSET  DIRECTION   TYPE  DESTINATION RULE
> notification-service.proxycfg-demo.svc.cluster.local      80    -       outbound    EDS   notification.proxycfg-demo
> notification-service.proxycfg-demo.svc.cluster.local      80    v1      outbound    EDS   notification.proxycfg-demo
> ```
>
> Both the subsetless cluster and the `v1` subset cluster exist. The last column names the `DestinationRule` responsible — an empty value there means the cluster was generated from the Service alone, with default policy, which is the cluster-level equivalent of Part 2's empty `VIRTUAL SERVICE` column.
>
> `--fqdn` is what makes this command usable. Without it you get every cluster the proxy knows about, which on a real cluster is hundreds of rows. `--port` and `--subset` narrow further.

## The TYPE column: how endpoints are found

`TYPE` is the cluster's **discovery type**, and it determines where the addresses in stage four come from:

| Type | Means | Seen on |
| --- | --- | --- |
| `EDS` | endpoints are pushed dynamically by `istiod` | ordinary Kubernetes Services — the common case |
| `ORIGINAL_DST` | use the destination the connection was originally addressed to | inbound clusters; `PassthroughCluster` |
| `STATIC` | a fixed list of addresses in the cluster itself | `ServiceEntry` with explicit endpoints |
| `STRICT_DNS` / `LOGICAL_DNS` | resolve a hostname with DNS, re-resolving periodically | external hosts via `ServiceEntry` with `resolution: DNS` |

`EDS` is the one to expect and the one that makes stage four a separate question: the cluster can exist with a perfectly good definition and have an empty endpoint list, because the endpoints arrive over their own discovery channel.

`ORIGINAL_DST` connects back to [Part 1](./course-01-capture-and-listeners.md) — it is the type that makes a single inbound listener able to serve any application port, by recovering the pre-redirect destination from the kernel.

## Endpoints: the addresses, right now

An **endpoint** is a real address: a pod IP and a port. Stage four resolves the cluster name into the set of them currently usable.

> [!TIP]
> **Try it — what the cluster resolves to**
>
> ```sh
> istioctl proxy-config endpoint deploy/tester -n proxycfg-demo \
>   --cluster "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local"
> ```
>
> Expect something like:
>
> ```text
> ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
> 10.244.0.12:8084     HEALTHY     OK                outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local
> ```
>
> One healthy endpoint, on the **container** port 8084 rather than the Service port 80. That is not a discrepancy: the proxy connects directly to the pod, so the Service port appears only in the cluster *name* while the connection goes to the target port. `kube-proxy` is not involved at all — the sidecar has the endpoint list and load balances itself.
>
> Note the quoting: the cluster name contains `|`, which is a shell pipe. Without quotes the command becomes four commands.

## Two columns, two different health questions

`STATUS` and `OUTLIER CHECK` look like the same information and are not:

| Column | Source | Says |
| --- | --- | --- |
| `STATUS` | Kubernetes readiness, delivered via EDS | is this pod ready to receive traffic, according to the cluster? |
| `OUTLIER CHECK` | **this proxy's own** observations | has this proxy ejected the endpoint after repeated failures? |

Outlier detection is per-proxy and per-cluster: each sidecar independently counts consecutive errors from each endpoint and temporarily removes the bad ones. So an endpoint can be `HEALTHY` (Kubernetes is happy) and `FAILED` (this client has given up on it), and two different client proxies can disagree about the same pod at the same moment.

That produces a distinctive symptom: a service failing from one caller and working from another, with nothing wrong on the destination. Checking `OUTLIER CHECK` from the complaining client's proxy is how you identify it in one command.

## An empty endpoint list

This is where "the configuration is perfect and nothing works" is finally explained. An empty list under an existing cluster has a short set of causes:

```text
   cluster exists, endpoints empty
        ├── no pods match the Service selector            → check the Service's selector
        ├── pods exist but are not Ready                  → check readiness probes
        ├── subset labels match no pod                    → the DestinationRule subset is wrong
        └── every endpoint ejected by outlier detection   → OUTLIER CHECK on the others
```

The third is the one manufactured by a well-meaning fix: adding a `DestinationRule` subset to satisfy a dangling reference, with labels no pod carries. The dangling reference is resolved and the traffic still fails — with a different response flag, which [module 040-02](../module-02/course.md) uses as the discriminator.

The distinction to hold: **a missing cluster and an empty cluster are different failures.** One means the route names something that does not exist; the other means it exists and has nothing behind it. Both produce a `503`, and the access log's response flag tells them apart.

> [!WARNING]
> **Pitfalls at the cluster and endpoint stages**
>
> - **Getting the cluster name slightly wrong.** `--cluster` needs the exact four-field string including the empty subset field in `outbound|80||host`, and `|` must be quoted in a shell.
> - **Expecting the Service port in the endpoint list.** Endpoints are pod IPs on the **container** port. Port 80 is in the cluster name; port 8084 is where the connection goes.
> - **Treating `HEALTHY` as proof the application is well.** It reflects Kubernetes readiness only.
> - **Ignoring `OUTLIER CHECK`.** An ejected endpoint is invisible in Kubernetes and explains "it fails from this caller only".
> - **Adding a subset to make an `IST0101` disappear.** If its labels match no pod you have replaced a missing cluster with an empty one — still broken, and now harder to diagnose.
> - **Dumping clusters unfiltered.** Always `--fqdn`; a sidecar knows about every Service in the mesh.

> *The cluster is a definition and the endpoints are a live answer — which is why a perfect cluster can have nothing behind it.*

## Reference

- [Envoy cluster manager](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/cluster_manager) — what a cluster is and the discovery types in the `TYPE` column.
- [Outlier detection](https://istio.io/latest/docs/reference/config/networking/destination-rule/#OutlierDetection) — the `DestinationRule` fields behind the `OUTLIER CHECK` column.
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — subsets, and how a subset's labels select pods.
- `istioctl proxy-config endpoint --help` — `--cluster`, `--address`, `--port` and `--status` for filtering large endpoint sets.
