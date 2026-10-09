# Overview: Debug A 503 Caused By A Missing Subset (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the starting workloads, applies broken Istio configuration, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. The `demo` profile turns on Envoy access logging, which this module relies on.
- Namespace **`fivezerothree-demo`**, labelled `istio-injection=enabled`. Every pod shows `2/2`: the application container plus its `istio-proxy` sidecar proxy (Envoy).

  | Workload | What it is |
  | --- | --- |
  | `notification-service-v1` | Deployment with the label `version: v1`, behind the Service `notification-service` on port `80` (named `http`) |
  | `tester` | Client pod with `curl`; send test requests from here |

- **A live `503`, on purpose.** A `DestinationRule` named `notification` defines only the subset `v1`, and a `VirtualService` named `notification` routes to the subset `v2`. Every request fails before it leaves the `tester` pod.

## Helpers

Paste these once in each new terminal. `send_request` sends one `POST` to `notification-service` from the `tester` pod and prints the status code. `last_log` prints the last access log line of the `tester` proxy and of the `notification-service-v1` proxy.

```sh
send_request() {
  kubectl -n fivezerothree-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
}
last_log() {
  echo "tester:";      kubectl -n fivezerothree-demo logs deploy/tester -c istio-proxy --tail=1
  echo "destination:"; kubectl -n fivezerothree-demo logs deploy/notification-service-v1 -c istio-proxy --tail=1
}
```

Use them like this: `send_request`, then `last_log`.

## Practice tasks

- Run `send_request` and `last_log`. Write down the response flag and predict what the chain will show before you run any `proxy-config` command.
- Fix it the wrong way: add a `v2` subset with the label `version: v2` to the `DestinationRule` (`kubectl -n fivezerothree-demo edit destinationrule notification`). Send a request and watch the flag change from `NC` to `UH`. Then remove the subset again.
- Fix it the right way by routing to `v1`, and prove the fix with a request, the route table and `istioctl analyze`.
- With correct routing in place, scale `notification-service-v1` to zero and find the flag for that state. Scale it back to one.
- Rename the Service port from `http` to `tcp` and check the `tester` proxy's port-80 listener for the `Cluster:` hand-off. Then rename it back.
