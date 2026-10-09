# Routes

Astronaut, the listener on port 80 handed the signal to something called `Route: 80`. That object is the flight plan table the communications officer reads before deciding where a signal flies. This part shows what a route configuration holds, how Envoy picks the right part of it, and how to read it when a rule does not behave.

## From listener to route configuration

A **route configuration** is the ordered decision table that turns an HTTP request into the name of a cluster (a destination squadron). Istio names it after the **port**, not after the Service. That is why the listener's `DESTINATION` column said `Route: 80`.

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

There is one route configuration per port, with many **virtual hosts** inside it, one per destination. That structure explains a detail that surprises people: a sidecar's port-80 route configuration has entries for **every** Service in the mesh that listens on port 80, not only the ones this workload calls. Cutting that set down is the job of the `Sidecar` resource, and it is why a sidecar's configuration grows with the cluster rather than with your app.

## Virtual host selection is by Host header

Envoy picks the virtual host by matching the request's `Host` header (or the HTTP/2 `:authority` header) against each virtual host's `domains` list. It does **not** pick by the IP address the connection went to.

Take a real case. A client connects to `notification-service` but sets `Host: nosuchhost.local`. No virtual host has that domain, so the sender's proxy answers `404` with the response flag `NR` (no route), even though the packets went to the right address. The rule: **change the `Host` header and you change the routing.**

Istio generates the `domains` list for you. It holds the short name, the name with the namespace, the fully qualified domain name (FQDN), and the ClusterIP. That is why `curl http://notification-service/` works from inside the same namespace: the short name is one of the domains.

## Reading the table

The `route` subcommand shows the route configuration as a table and as JSON. Both views are useful, and this section shows when each one tells the truth.

<!-- astrona:playground:renew -->

### See the rules behind port 80

Ask the test ship for the route configuration named `80`:

```sh
istioctl proxy-config route deploy/tester -n proxycfg-demo --name 80
```

You should see something like:

```text
NAME  VHOST NAME                                              DOMAINS                                    MATCH     VIRTUAL SERVICE
80    notification-service.proxycfg-demo.svc.cluster.local:80  notification-service, 10.96.x.x           /*        notification.proxycfg-demo
```

There are five columns, and the last one is the one to read first. `VIRTUAL SERVICE` names the Istio object that produced this route. An **empty** value there means Istio built a default route from the Service alone. That is a fast, exact way to find out that your `VirtualService` is not applied to this host, without reading any YAML.

`--name 80` picks the route configuration by the name the listener handed you. Without it you get every route configuration the proxy holds. `--name` also accepts the inbound form (`inbound|8084||`). On a gateway the names are different again, for example `http.8080` or `https.443.https.my-gateway.istio-system`, because they follow the gateway's server blocks rather than plain ports.

### Where the table lies

The `MATCH` column shows `/*` for almost every route. That is not the whole match. It is a summary that shows only the path condition. A rule that matches on a header, a method or a query parameter still shows `/*`, which makes the table misleading for exactly the debugging you are most likely to do.

The JSON output holds the real conditions, in the order Envoy checks them. Pull out the names, matches and clusters:

```sh
istioctl proxy-config route deploy/tester -n proxycfg-demo --name 80 -o json \
  | grep -E '"name"|"exact_match"|"prefix"|"cluster"' | head -20
```

You should see something like:

```text
  "name": "80",
        "name": "testing",
            "exact_match": "true",
        "cluster": "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local",
        "cluster": "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local",
```

There are two routes, in the order your `VirtualService` declared them. The first is guarded by an exact match on the `testing` header; the second has no condition. This is the view in which a shadowed rule becomes visible: a rule listed below a rule with no condition can never be reached, however correct it looks in your editor.

For anything more than a quick `grep`, pipe `-o json` into `jq`. The route list lives at `.[].dynamicRouteConfigs[].routeConfig.virtualHosts[].routes[]`, and pulling `{match, route: {cluster}}` from each entry gives you the decision table in a readable shape.

## What the route stage produces

The output of stage two is a **cluster name**: a string, nothing more. The route does not know whether that cluster exists, how many endpoints it has, or whether any of them are healthy. It names a destination and hands it over.

That separation is why each failure looks different, and why it pays to walk the chain in order:

| At the route stage | Symptom |
| --- | --- |
| no virtual host matched the `Host` header | `404`, flag `NR` |
| a rule matched, but the wrong one | the wrong version answers; a `200` from the wrong place |
| the rule you wrote is never checked (shadowed) | your rule has no effect at all |
| the named cluster does not exist | `503`, but that failure belongs to the cluster stage |

The last row marks the boundary. A route that points at a cluster that does not exist is still a **valid route**: the route stage did its job. What fails is the next stage, and the cluster name the route produced is how you cross into it.

## Common pitfalls

> [!WARNING]
> - **Reading the table output for a match problem.** Every rule shows `/*`. Header, method and query conditions are only in `-o json`.
> - **Ignoring an empty `VIRTUAL SERVICE` column.** It means no `VirtualService` applies to that host, and Istio built a default. That is a finding, not a formatting quirk.
> - **Assuming routing follows the address dialled.** The virtual host is chosen by the `Host` header. A rewritten or overridden `Host` lands somewhere else, or nowhere.
> - **Asking the destination proxy about a client-side routing problem.** The **sending** proxy applies `VirtualService` rules. Ask the client.
> - **Forgetting that a sidecar carries routes for the whole mesh.** Most of the port-80 route configuration has nothing to do with this workload. Narrow with `--name` and read the virtual host you care about.

> *A route produces a name, not a destination. Everything after it is a question about whether that name resolves.*
