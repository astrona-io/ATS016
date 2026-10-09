# Routes

The listener on port 80 handed the request to something called `Route: 80`. That object is the table of routing rules the sidecar proxy reads before it decides where an HTTP request goes. This part shows what a route configuration holds, how Envoy picks the right part of it, and how to read it when a rule does not behave.

## From listener to route configuration

A **route configuration** is the ordered list of rules that turns an HTTP request into the name of a cluster. A cluster is Envoy's name for a group of destination pods plus the settings for reaching them. Istio names the route configuration after the **port**, not after the Service, which is why the listener's `DESTINATION` column said `Route: 80`.

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

There is one route configuration per port, and inside it there are many **virtual hosts**, one per destination. That structure explains a detail that surprises people. A sidecar's port-80 route configuration has entries for **every** Service in the mesh that listens on port 80, not only the ones this workload calls. Cutting that set down is the job of the `Sidecar` resource, an Istio resource that limits which Services a proxy receives configuration for. Without it, a sidecar's configuration grows with the cluster rather than with your application.

## Virtual host selection is by Host header

Envoy picks the virtual host by matching the request's `Host` header (or the HTTP/2 `:authority` header) against each virtual host's `domains` list. It does **not** pick by the IP address the connection went to.

A concrete case shows the effect. A client connects to `notification-service` but sets `Host: nosuchhost.local`. No virtual host has that domain, so the client's sidecar proxy answers `404` with the response flag `NR` (no route), even though the packets went to the right address. A response flag is the short code Envoy writes in its access log to say why a request ended the way it did. The general rule is simple: **change the `Host` header and you change the routing.**

Istio builds the `domains` list for you. It holds the short name, the name with the namespace, the fully qualified domain name (FQDN), and the ClusterIP. That is why `curl http://notification-service/` works from inside the same namespace: the short name is one of the domains.

## Reading the table

The `route` subcommand shows the route configuration as a table or as JSON. Both views are useful, but only one of them shows every match condition. Ask the `tester` proxy for the route configuration named `80`:

<!-- astrona:playground:renew -->

```sh
istioctl proxy-config route deploy/tester -n proxycfg-demo --name 80
```

You should see something like:

```text
NAME  VHOST NAME                                              DOMAINS                                    MATCH     VIRTUAL SERVICE
80    notification-service.proxycfg-demo.svc.cluster.local:80  notification-service, 10.96.x.x           /*        notification.proxycfg-demo
```

There are five columns, and the last one is the one to read first. `VIRTUAL SERVICE` names the Istio object that produced this route. An **empty** value there means Istio built a default route from the Service alone. That is a fast, exact way to find out that your `VirtualService` does not apply to this host, without reading any YAML.

`--name 80` picks the route configuration by the name the listener gave you. Without it you get every route configuration the proxy holds. `--name` also accepts the inbound form (`inbound|8084||`). On a gateway the names are different again, for example `http.8080`, because they follow the gateway's server blocks rather than plain ports.

The `MATCH` column shows `/*` for almost every route, and that is not the whole match. It is a summary that shows only the path condition. A rule that matches on a header, a method or a query parameter still shows `/*`, which makes the table misleading for the debugging you are most likely to do. The JSON output holds the real conditions, in the order Envoy checks them. Pull out the names, matches and clusters:

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

There are two routes, in the order your `VirtualService` declared them. The first is guarded by an exact match on the `testing` header; the second has no condition. This is the view in which a shadowed rule becomes visible. A shadowed rule is one listed below a rule with no condition: Envoy checks rules in order and stops at the first match, so the shadowed rule can never be reached.

For anything more than a quick `grep`, pipe `-o json` into `jq`. The route list is at `.[].dynamicRouteConfigs[].routeConfig.virtualHosts[].routes[]`, and pulling `{match, route: {cluster}}` from each entry gives you the rule list in a readable shape.

## What the route stage produces

The output of the route stage is a **cluster name**: a string, nothing more. The route does not know whether that cluster exists, how many endpoints it has, or whether any of them are healthy. It names a destination and passes it on.

That separation is why each failure looks different, and why it pays to check the stages in order:

| At the route stage | Symptom |
| --- | --- |
| no virtual host matched the `Host` header | `404`, flag `NR` |
| a rule matched, but the wrong one | the wrong version answers; a `200` from the wrong place |
| the rule you wrote is never checked (shadowed) | your rule has no effect at all |
| the named cluster does not exist | `503`, but that failure belongs to the cluster stage |

The last row marks the boundary between two stages. A route that names a cluster that does not exist is still a **valid route**: the route stage did its job. What fails is the next stage.

You now know that the route stage picks a virtual host by the `Host` header, checks the rules in order, and produces one cluster name. You also know that the table hides header matches and the JSON does not. The cluster name is the input to the next stage, and the open question is what that name refers to.

## Common pitfalls

> [!WARNING]
> - **Reading the table output for a match problem.** Every rule shows `/*`. Header, method and query conditions are only in `-o json`.
> - **Ignoring an empty `VIRTUAL SERVICE` column.** It means no `VirtualService` applies to that host, and Istio built a default route.
> - **Assuming routing follows the address the client connected to.** The virtual host is chosen by the `Host` header. A rewritten `Host` lands somewhere else, or nowhere.
> - **Asking the destination proxy about a client-side routing problem.** The **sending** proxy applies `VirtualService` rules. Ask the client.
> - **Forgetting that a sidecar carries routes for the whole mesh.** Most of the port-80 route configuration has nothing to do with this workload. Narrow with `--name` and read the virtual host you care about.
