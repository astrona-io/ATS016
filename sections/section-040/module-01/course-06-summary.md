# Summary

When every outside check passes and a request still does the wrong thing, the sidecar proxy's own configuration is the ground truth. This module read that configuration one stage at a time with `istioctl proxy-config`.

## What you learned

Traffic reaches the sidecar proxy because the `istio-init` container writes `iptables` rules into the pod. Connections the application opens are redirected to port 15001, and connections arriving for the application are redirected to port 15006, so the application needs no change. A listener accepts the connection and its `DESTINATION` column says what comes next: a `Route:`, a `Cluster:` or `PassthroughCluster`. On a shared port, Envoy picks a filter chain by the detected protocol, so a port whose protocol Istio does not know can miss HTTP routing.

A route configuration is named after the port, for example `Route: 80`, and holds one virtual host per destination. Envoy chooses the virtual host by the `Host` header, then checks the rules in order and stops at the first match. An empty `VIRTUAL SERVICE` column means no `VirtualService` applies to that host. The table's `MATCH` column shows only the path, so header matches are visible only in `-o json`.

A cluster name has four fields, `direction|port|subset|fqdn`, and a subset cluster exists only if a `DestinationRule` defines that subset. Endpoints are pod IPs on the container port. `STATUS` reports Kubernetes readiness, and `OUTLIER CHECK` reports this proxy's own decision to stop using an endpoint. A missing cluster gives `503` with the flag `NC`; an empty cluster gives `503` with the flag `UH`.

The destination pod's proxy applies server-side policy. `PeerAuthentication` and `AuthorizationPolicy` live on its 15006 listener, and the request continues to the `inbound|<port>||` cluster of type `ORIGINAL_DST`. `istioctl proxy-config secret` shows the workload certificate, valid for about 24 hours, and the mesh root certificate. The key facts to remember are these:

- Walk listener, route, cluster and endpoint on the client, and carry each name to the next command.
- Narrow every query with `--port`, `--name`, `--fqdn` or `--cluster`, and quote cluster names.
- The response flag maps a symptom to a stage: `NR` to the route, `NC` to the cluster, `UH` to the endpoints.
- When the client side is correct, move to the destination proxy: its inbound cluster, its policy and its access log.

<!-- astrona:playground:destroy -->
