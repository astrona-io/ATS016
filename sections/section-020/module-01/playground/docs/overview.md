# Overview: Debug Conflicting And Shadowed Routes (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the starting workloads, applies routing that is in conflict on purpose, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. `istiod` is Istio's control plane: it turns Istio resources into proxy configuration and sends it to every sidecar proxy.
- Namespace **`conflict-demo`**, labelled `istio-injection=enabled`. Every pod shows `2/2`: the application container plus its `istio-proxy` sidecar proxy (Envoy), which handles all inbound and outbound traffic of the pod.

  | Workload | What it is |
  | --- | --- |
  | `notification-service-v1` | Deployment with the label `version: v1`; answers `["EMAIL"]` |
  | `notification-service-v2` | Deployment with the label `version: v2`; answers `["EMAIL","SMS"]` |
  | `notification-service` | Service on port `80` in front of both versions |
  | `tester` | Client pod with `curl`; send test requests from here |

- **Routing in conflict, on purpose.** A `DestinationRule` named `notification` defines the subsets `v1` and `v2`. A `VirtualService` named `notification` has its catch-all route above its header rule for `testing: true`. A second `VirtualService`, `notification-extra`, claims the same host.

## Helpers

Paste these once in each new terminal. `send_requests` sends ten `POST` requests to `notification-service` from the `tester` pod and prints each distinct reply once; pass a header as the first argument, for example `send_requests "testing: true"`. `show_routes` prints the clusters and header matches in the route configuration for port `80` of the `tester` proxy.

```sh
send_requests() {
  kubectl -n conflict-demo exec deploy/tester -- sh -c \
    "for i in \$(seq 1 10); do curl -s -X POST ${1:+-H \"$1\"} http://notification-service/notify; echo; done" | sort -u
}
show_routes() {
  istioctl proxy-config routes deploy/tester -n conflict-demo \
    --name 80 -o json | grep -E '"cluster"|"exact_match"|"prefix"'
}
```

Use them like this: `send_requests`, `send_requests "testing: true"`, `show_routes`.

## Practice tasks

- Run `show_routes` and `istioctl analyze -n conflict-demo` before you change anything. Decide which `VirtualService` the proxy is using, and why the header route is missing.
- Fix only the rule order in `notification`, leave `notification-extra` in place, and run `send_requests "testing: true"` and `show_routes`. Decide whether you would ship the result.
- Delete `notification-extra` instead, and watch which symptom changes and which one stays.
- Give the second `VirtualService` a different host and run `istioctl analyze` again. The `IST0109` message should disappear.
- Add a third rule matching `uri: prefix: /notify` below the catch-all, then confirm with `show_routes` that it can never be reached.
- Change the header value in the match to `exact: true` without quotes and apply it. Read which stage of the API server rejects it.
