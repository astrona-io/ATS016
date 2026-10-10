# Overview: Find Configuration Errors With istioctl analyze (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the starting workloads, applies some broken Istio configuration, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. `istiod` is Istio's control plane: it turns Istio resources into proxy configuration and sends it to every sidecar proxy.
- Namespace **`analyze-demo`**, labelled `istio-injection=enabled`. Every pod shows `2/2`: the application container plus its `istio-proxy` sidecar proxy (Envoy), which handles all inbound and outbound traffic of the pod.

  | Workload | What it is |
  | --- | --- |
  | `notification-service-v1` | Deployment with the label `version: v1`, behind the Service `notification-service` on port `80`; it answers `["EMAIL"]` |
  | `tester` | Client pod with `curl`; send test requests from here |

- **Broken Istio configuration, on purpose.** A `DestinationRule` named `notification` defines only the subset `v1`. A `VirtualService` named `notification` routes to the subset `v3` and lists two gateways: `mesh`, so the sidecar proxies use it, and a `Gateway` named `missing-gateway` that does not exist. The API server accepted both objects without an error. A request to `notification-service` returns `503`.

## Helpers

Paste these once in each new terminal. `send_request` sends one `POST` to `notification-service` from the `tester` pod and prints the status code. `show_routing` prints the YAML of the `VirtualService` and the `DestinationRule` in the namespace.

```sh
send_request() {
  kubectl -n analyze-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
}
show_routing() {
  kubectl -n analyze-demo get virtualservice,destinationrule -o yaml
}
```

Use them like this: `send_request`, `show_routing`.

## Practice tasks

- Run `istioctl analyze -n analyze-demo` before you run `show_routing`. Then read the YAML and check whether the analyzer found every problem you can see.
- Remove the injection label with `kubectl label namespace analyze-demo istio-injection-` and run the analyzer again. Predict the code and the severity of the new message before you look. Put the label back with `kubectl label namespace analyze-demo istio-injection=enabled`.
- Delete the `DestinationRule` with `kubectl -n analyze-demo delete destinationrule notification` and predict the message before you run the analyzer again.
- Save the `VirtualService` and the `DestinationRule` to one file and compare `istioctl validate -f`, `istioctl analyze --use-kube=false` and `istioctl analyze -n analyze-demo` on it. Note which of the three reports the missing subset.
- Run `istioctl analyze -n analyze-demo --failure-threshold Warning` and print `$?`. Fix the `VirtualService` and compare the exit code with the default threshold.
