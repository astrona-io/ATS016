# Part 2 — Routes

> Prerequisite: [Part 1 — Capture And Listeners](./course-01-capture-and-listeners.md). Next: [Part 3 — Clusters And Endpoints](./course-03-clusters-and-endpoints.md).

Stage one ended by handing a connection to something called `Route: 80`. This part is that object: what a route configuration contains, how one of its virtual hosts is selected, and how to read it when a rule is not behaving.

## From listener to route configuration

A **route configuration** is the ordered decision table that turns an HTTP request into the name of a cluster. Istio names it after the **port**, not the service — which is why the listener's `DESTINATION` column said `Route: 80`.

```text
   Listener 0.0.0.0:80  ──▶  RouteConfiguration "80"
                                 │
                                 ├─ VirtualHost  notification-service.proxycfg-demo.svc.cluster.local:80
                                 │     domains: [notification-service,
                                 │               notification-service.proxycfg-demo,
                                 │               notification-service.proxycfg-demo.svc.cluster.local,
                                 │               10.96.44.31]          ← the ClusterIP too
                                 │     routes:  [ rule, rule, ... ]    ← your VirtualService, in order
                                 │
                                 └─ VirtualHost  (every other service this proxy knows on port 80)
```

One route configuration per port, many virtual hosts inside it. That structure explains a detail that surprises people: a sidecar's port-80 route configuration contains entries for **every** service in the mesh that listens on port 80, not only the ones this workload calls. Narrowing that set is what the `Sidecar` resource is for, and why the configuration size of a sidecar scales with the cluster rather than with your application.

## Virtual host selection is by Host header

Envoy picks the virtual host by matching the request's `Host` (or HTTP/2 `:authority`) header against the `domains` list. **Not** by the IP address the connection was made to.

The consequence is worth stating as a rule, because it produces failures that look impossible: **change the `Host` header and you change the routing**, even though the packets went to the same address. A client that sets `Host: nosuchhost.local` while connecting to `notification-service` matches no virtual host and gets a `404` with response flag `NR` — a result [module 050-01](../../section-050/module-01/course.md) produces deliberately.

The `domains` list is generated for you and includes the short name, the namespace-qualified name, the fully qualified name, and the ClusterIP. That is why `curl http://notification-service/` from inside the same namespace works: the short name is one of the domains.

## Reading the table

> [!TIP]
> **Try it — the rules behind port 80**
>
> ```sh
> istioctl proxy-config route deploy/tester -n proxycfg-demo --name 80
> ```
>
> Expect something like:
>
> ```text
> NAME  VHOST NAME                                              DOMAINS                                    MATCH     VIRTUAL SERVICE
> 80    notification-service.proxycfg-demo.svc.cluster.local:80  notification-service, 10.96.x.x           /*        notification.proxycfg-demo
> ```
>
> Five columns, and the last is the one to read first: `VIRTUAL SERVICE` names the Istio object that produced this route. An **empty** value there means Istio generated a default route from the Service alone — which is a precise, fast way to discover that your `VirtualService` is not being applied to this host at all, without reading a line of YAML.

`--name 80` selects the route configuration by the name the listener handed you. Without it you get every route configuration the proxy holds. Two other useful narrowings: `--name` accepts the inbound form too (`inbound|8084||`), and on a gateway the names are different again — `http.8080`, `https.443.https.my-gateway.istio-system` — reflecting the gateway's server blocks rather than plain ports.

## Where the table lies

The `MATCH` column shows `/*` for almost every route. That is not the whole match — it is a summary that shows the path condition only. A rule matching on a header, a method or a query parameter still displays as `/*`, which makes the tabular output actively misleading for exactly the debugging you are most likely to be doing.

The JSON output carries the real conditions, in evaluation order.

> [!TIP]
> **Try it — the match conditions, in order**
>
> ```sh
> istioctl proxy-config route deploy/tester -n proxycfg-demo --name 80 -o json \
>   | grep -E '"name"|"exact_match"|"prefix"|"cluster"' | head -20
> ```
>
> Expect something like:
>
> ```text
>   "name": "80",
>         "name": "testing",
>             "exact_match": "true",
>         "cluster": "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local",
>         "cluster": "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local",
> ```
>
> Two routes in the order your `VirtualService` declared them: the first guarded by an exact match on the `testing` header, the second unguarded. This is the view in which a shadowed rule ([section 020](../../section-020/module-01/course-01-virtualservice-to-route-table.md)) becomes visible — a rule listed below an unconditional one will never be reached, however correct it looks in your editor.

For anything beyond a grep, `-o json` piped to `jq` is the practical form. The route array lives at `.[].dynamicRouteConfigs[].routeConfig.virtualHosts[].routes[]`, and pulling `{match, route: {cluster}}` from each gives you the decision table in a readable shape.

## What the route stage produces

The output of stage two is a **cluster name** — a string, nothing more. The route does not know whether that cluster exists, how many endpoints it has, or whether any of them are healthy. It names a destination and hands over.

That separation is why the failure modes are distinct and why the chain is worth walking in order:

| At the route stage | Symptom |
| --- | --- |
| no virtual host matched the `Host` header | `404`, flag `NR` |
| a rule matched, but the wrong one | the wrong version answers; a `200` from the wrong place |
| the rule you wrote is never evaluated (shadowed) | your rule has no effect at all |
| the named cluster does not exist | `503` — but that failure belongs to [Part 3](./course-03-clusters-and-endpoints.md) |

The last row is the important boundary. A route pointing at a non-existent cluster is a **valid route**; the route stage did its job. What fails is the next stage, and reading the cluster name it produced is how you cross into it.

> [!WARNING]
> **Pitfalls at the route stage**
>
> - **Reading the tabular output for a match problem.** Every rule shows `/*`. Header, method and query conditions are only in `-o json`.
> - **Ignoring an empty `VIRTUAL SERVICE` column.** It means no `VirtualService` is applied to that host, and Istio generated a default. That is a finding, not a formatting quirk.
> - **Assuming routing follows the address dialled.** The virtual host is chosen by the `Host` header. A rewritten or overridden `Host` lands elsewhere or nowhere.
> - **Querying the destination proxy for a client-side routing problem.** `VirtualService` rules are applied by the **sending** proxy. Ask the client.
> - **Forgetting that a sidecar carries routes for the whole mesh.** Most of the port-80 route configuration has nothing to do with this workload; narrow with `--name` and read the virtual host you care about.

> *A route produces a name, not a destination — everything after it is a question about whether that name resolves.*

## Reference

- [Envoy HTTP routing](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/http/http_routing) — virtual host selection, domain matching and first-match evaluation.
- [Route configuration proto](https://www.envoyproxy.io/docs/envoy/latest/api-v3/config/route/v3/route.proto) — the exact JSON shape you are grepping, useful for building a `jq` filter.
- `istioctl proxy-config route --help` — `--name`, `--output`, and the gateway-specific name forms.
- [Sidecar resource](https://istio.io/latest/docs/reference/config/networking/sidecar/) — how to cut a proxy's route configuration down to the hosts a workload actually calls.
