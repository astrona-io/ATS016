# Overview: Read The Proxy Configuration (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the starting workloads, applies working routing, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. `istiod` is Istio's control plane: it turns Istio resources into proxy configuration and sends it to every sidecar proxy.
- Namespace **`proxycfg-demo`**, labelled `istio-injection=enabled`. Every pod shows `2/2`: the application container plus its `istio-proxy` sidecar proxy (Envoy), which handles all inbound and outbound traffic of the pod.

  | Workload | What it is |
  | --- | --- |
  | `notification-service-v1` | Deployment with the label `version: v1`, behind the Service `notification-service` on port `80` (named `http`), container port `8084` |
  | `tester` | Client pod with `curl`; send test requests from here |

- **Working routing.** A `DestinationRule` named `notification` defines the subset `v1`. A `VirtualService` named `notification` sends requests with the header `testing: true` to `v1`, and every other request to `v1` as well. Nothing is broken.

## Helpers

Paste these once in each new terminal. `send_request` sends one `POST` to `notification-service` from the `tester` pod and prints the status code. `walk_chain` prints the four client-side stages for `notification-service`: the port-80 listener, the clusters named in the port-80 route, the clusters for the host, and the endpoints of the `v1` cluster.

```sh
send_request() {
  kubectl -n proxycfg-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
}
walk_chain() {
  istioctl proxy-config listener deploy/tester -n proxycfg-demo --port 80
  istioctl proxy-config route deploy/tester -n proxycfg-demo --name 80 -o json | grep '"cluster"' | sort -u
  istioctl proxy-config cluster deploy/tester -n proxycfg-demo --fqdn notification-service.proxycfg-demo.svc.cluster.local
  istioctl proxy-config endpoint deploy/tester -n proxycfg-demo \
    --cluster "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local"
}
```

Use them like this: `send_request`, `walk_chain`.

## Practice tasks

- Run `walk_chain` and write down the exact name each stage gives to the next.
- Edit the `VirtualService` (`kubectl -n proxycfg-demo edit virtualservice notification`) so the header rule routes to a subset `v3`. Send a request with `-H "testing: true"`, then find the exact stage where the chain breaks. Put `v1` back afterwards.
- Scale `notification-service-v1` to zero and watch the endpoint list empty while the cluster stays. Scale it back to one.
- Compare `istioctl proxy-config cluster deploy/tester -n proxycfg-demo` (outbound) with the same command against `deploy/notification-service-v1` (inbound).
- Read the `tester` proxy's certificates with `istioctl proxy-config secret deploy/tester -n proxycfg-demo` and work out when the workload certificate expires.
- Run `istioctl proxy-config all deploy/tester -n proxycfg-demo -o json | wc -l` once, to see how much output the narrowing flags save you.
