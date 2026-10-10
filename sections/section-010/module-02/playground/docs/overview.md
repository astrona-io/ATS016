# Overview: Summarise A Workload With describe, Capture A Cluster With bug-report (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the starting workloads, applies four Istio objects, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. `istiod` is Istio's control plane: it turns Istio resources into proxy configuration and sends it to every sidecar proxy.
- Namespace **`describe-demo`**, labelled `istio-injection=enabled`. Every pod shows `2/2`: the application container plus its `istio-proxy` sidecar proxy (Envoy), which handles all inbound and outbound traffic of the pod.

  | Workload | What it is |
  | --- | --- |
  | `notification-service-v1` | Deployment with the label `version: v1`, behind the Service `notification-service` on port `80` (port name `http`) |
  | `tester` | Client pod with `curl`; send test requests from here |

- **Four Istio objects that all apply to `notification-service`:** a namespace-wide `PeerAuthentication` named `default` in `STRICT` mode, a `DestinationRule` named `notification` with the subset `v1`, a `VirtualService` named `notification` that routes to it, and an `AuthorizationPolicy` named `notification-post-only` that allows only `POST`.
- Nothing is broken. A `POST` to `http://notification-service/notify` returns `200`, and a `GET` returns `403`.
- Every sidecar proxy starts with its Envoy log scopes at `warning`, except `misc`, which is at `error`.

## Helpers

Paste these once in each new terminal. `POD` holds the name of the `notification-service` pod. `send_method` sends one request with the HTTP method you name from the `tester` pod and prints the status code. `show_levels` prints the `rbac`, `router` and `upstream` log levels of the `notification-service` proxy.

```sh
export POD=$(kubectl -n describe-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
send_method() {
  kubectl -n describe-demo exec deploy/tester -- \
    curl -s -o /dev/null -w "$1 %{http_code}\n" -X "$1" http://notification-service/notify
}
show_levels() {
  istioctl proxy-config log "$POD" -n describe-demo | grep -E '(rbac|router|upstream):'
}
```

Use them like this: `send_method GET`, `show_levels`.

## Practice tasks

- Write down what you expect `istioctl x describe pod $POD -n describe-demo` to say about mTLS, routing and authorization. Then run it and check yourself.
- Add a workload-level `PeerAuthentication` that selects `app: notification-service` with mode `PERMISSIVE`. Predict the effective mode, check it with `describe`, then delete the new object.
- Change the `AuthorizationPolicy` selector to a label no pod carries and run `describe` again. Send a `GET` with `send_method GET` and explain the new status code. Put the selector back.
- Remove `name: http` from the `notification-service` Service port and compare the port line in the `describe` output before and after. Put the name back.
- Raise `rbac:debug`, send a `GET` and a `POST`, and find both decisions in the `istio-proxy` log. Put the level back to `warning` and check it with `show_levels`.
- Run `istioctl bug-report` once with `--include describe-demo/notification-service-v1 --include istio-system/istiod --duration 5m` and once with `--include describe-demo,istio-system/notification-service-v1,istiod --duration 5m`. Add `--output-dir` with a different folder each time so the second archive does not replace the first. Compare the `include:` line at the top of each output and the `bug-report/proxies/` and `bug-report/istio/` folders in the two archives, and explain why the first archive holds no proxy data.
