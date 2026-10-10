# Clusters And Endpoints

The route stage produced a name. This part is about what that name refers to, how Istio builds it, and what happens when it refers to nothing. A route that names a destination that does not exist is one of the most common failures in an Istio mesh, so this is the stage where many investigations end.

## What a cluster is

In Envoy's words, a **cluster** is a named group of upstream hosts plus the rules for connecting to them: the load-balancing method, connection pool limits, outlier detection, TLS settings and timeouts. "Upstream" means the destination side of a connection. A cluster is the object your `DestinationRule` configures.

A cluster is a *definition*, not a list of addresses. The addresses are the fourth stage, the endpoints, which arrive separately and change on their own. That split is what lets a pod be replaced without touching routing: the cluster stays the same, and only its endpoints change.

## Reading the name

Istio names every cluster with four fields separated by `|`, and the name alone tells you a lot. Here is the name of the `v1` cluster in your playground, taken apart:

```text
outbound | 80 | v1 | notification-service.proxycfg-demo.svc.cluster.local
   │       │     │                      │
   │       │     │                      └─ the destination's fully qualified domain name (FQDN)
   │       │     └──────────────────────── the subset, from a DestinationRule; EMPTY means "no subset"
   │       └────────────────────────────── the port (the SERVICE port, not the container port)
   └────────────────────────────────────── direction: outbound (leaving this pod) or inbound (arriving)
```

Two facts follow from this. The name `outbound|80||notification-service...`, with an empty third field, is the cluster without a subset. It always exists for a Service the proxy knows about, whether or not any `DestinationRule` exists. The name `outbound|80|v3|notification-service...` exists **only** if a `DestinationRule` defines a subset named `v3`. A route that names a subset with no cluster behind it is one of the most common causes of a `503` in Istio.

So the third field is where the `DestinationRule` and the `VirtualService` meet. The `VirtualService` writes a subset name into a route, and the `DestinationRule` makes a cluster with that name exist. Nothing checks that the two agree when you apply them, because the API server checks each object on its own. Ask the `tester` proxy which clusters it has for `notification-service`:

<!-- astrona:playground:renew -->

```sh
istioctl proxy-config cluster deploy/tester -n proxycfg-demo \
  --fqdn notification-service.proxycfg-demo.svc.cluster.local
```

You should see something like:

```text
SERVICE FQDN                                             PORT     SUBSET     DIRECTION     TYPE     DESTINATION RULE
notification-service.proxycfg-demo.svc.cluster.local     80       -          outbound      EDS      notification.proxycfg-demo
notification-service.proxycfg-demo.svc.cluster.local     80       v1         outbound      EDS      notification.proxycfg-demo
```

Both the cluster without a subset and the `v1` subset cluster exist. The last column names the `DestinationRule` behind each one. An empty value there means the cluster was built from the Service alone, with default settings, just as an empty `VIRTUAL SERVICE` column does at the route stage. `--fqdn` is what makes this command usable: without it you get every cluster the proxy knows, which on a real cluster is hundreds of rows. `--port` and `--subset` narrow it further.

## The TYPE column: how endpoints are found

The `TYPE` column is the cluster's **discovery type**. It decides where the addresses at the endpoint stage come from:

| Type | Means | Seen on |
| --- | --- | --- |
| `EDS` | `istiod` pushes the endpoints to the proxy as they change | ordinary Kubernetes Services, the common case |
| `ORIGINAL_DST` | use the address the connection was first sent to | inbound clusters; `PassthroughCluster` |
| `STATIC` | a fixed list of addresses inside the cluster itself | a `ServiceEntry` with explicit endpoints |
| `STRICT_DNS` / `LOGICAL_DNS` | look up a hostname with DNS, and look it up again from time to time | outside hosts through a `ServiceEntry` with `resolution: DNS` |

`EDS` (Endpoint Discovery Service) is the type to expect. It is also why the endpoints are a separate question: a cluster can exist with a correct definition and still have an empty endpoint list, because the endpoints arrive on their own channel. `ORIGINAL_DST` is the type that lets one inbound listener serve any application port. The `iptables` rules redirect every arriving connection to port 15006, and this cluster type sends it on to the address it was first sent to, which the Linux kernel recorded.

## Endpoints: the addresses, right now

An **endpoint** is a real address: a pod IP and a port. The fourth stage turns the cluster name into the set of endpoints that can be used right now. Ask for the endpoints of the `v1` cluster. Quote the name, because it contains `|`, which the shell reads as a pipe:

```sh
istioctl proxy-config endpoint deploy/tester -n proxycfg-demo \
  --cluster "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local"
```

You should see something like:

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.8:8084     HEALTHY     OK                outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local
```

There is one healthy endpoint, on the **container** port 8084 rather than the Service port 80. That is not a mistake. The sidecar proxy connects straight to the pod, so the Service port appears only in the cluster *name*, while the connection goes to the target port. `kube-proxy` plays no part here: the sidecar proxy holds the endpoint list and picks the pod itself.

## Two columns, two different health questions

`STATUS` and `OUTLIER CHECK` look like the same information, but they answer different questions from different sources:

| Column | Source | Says |
| --- | --- | --- |
| `STATUS` | Kubernetes readiness, delivered by EDS | is this pod ready for traffic, according to Kubernetes? |
| `OUTLIER CHECK` | **this proxy's own** observations | has this proxy removed the endpoint after repeated failures? |

Outlier detection is an Envoy feature that removes failing endpoints from load balancing for a while. It works per proxy and per cluster: each sidecar proxy counts errors from each endpoint on its own. So an endpoint can be `HEALTHY` (Kubernetes is satisfied) and `FAILED` (this client has stopped using it), and two client proxies can disagree about the same pod at the same moment. That gives a typical symptom: a service fails from one caller and works from another, with nothing wrong on the destination. Checking `OUTLIER CHECK` on the failing client's proxy finds it in one command.

## An empty endpoint list

An empty endpoint list under a cluster that exists explains the case where "the configuration is correct and nothing works". There are only a few causes:

- No pods match the Service selector. Check the Service's `selector`.
- Pods exist but are not ready. Check the readiness probes.
- The subset's labels match no pod. The `DestinationRule` subset is wrong.
- Outlier detection removed every endpoint. Check `OUTLIER CHECK`.

The third cause is the one a well-meant fix creates. Someone adds a `DestinationRule` subset to satisfy a reference that does not resolve, with labels no pod carries. The reference now resolves, and requests still fail, with a different response flag in the access log.

You now know that a cluster is a definition with a four-field name, and that its endpoints are a live list of pod addresses that arrives separately. Hold on to one distinction: **a missing cluster and an empty cluster are different failures.** In the first, the route names something that does not exist; in the second, it exists and has nothing behind it. Both give a `503`, and the access log's response flag tells them apart: `NC` (no cluster found) for the first, `UH` (no healthy upstream host) for the second. So far every command has asked the client's proxy. The destination pod has a proxy too, and some problems are visible only there.

## Common pitfalls

> [!WARNING]
> - **Getting the cluster name slightly wrong.** `--cluster` needs the exact four-field string, including the empty subset field in `outbound|80||host`, and `|` must be quoted in a shell.
> - **Expecting the Service port in the endpoint list.** Endpoints are pod IPs on the **container** port. Port 80 is in the cluster name; port 8084 is where the connection goes.
> - **Treating `HEALTHY` as proof the application works.** It reflects Kubernetes readiness only.
> - **Ignoring `OUTLIER CHECK`.** A removed endpoint is invisible in Kubernetes and explains "it fails from this caller only".
> - **Adding a subset only to make an `IST0101` analyzer error go away.** If its labels match no pod, you have swapped a missing cluster for an empty one: still broken, and harder to diagnose.
> - **Dumping clusters unfiltered.** Always use `--fqdn`. A sidecar knows about every Service in the mesh.
