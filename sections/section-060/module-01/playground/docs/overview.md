# Overview: Troubleshoot With Kiali (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio, the Prometheus and Kiali add-ons and the starting workloads, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. `istiod` is Istio's control plane: it sends configuration to every sidecar proxy.
- The **Prometheus** and **Kiali** add-ons from the Istio 1.30 release, in `istio-system`. Prometheus collects the metrics every sidecar proxy exposes. Kiali is the Istio console: it draws a graph from those metrics and checks the Istio objects it reads from the API server. It stores no data itself.
- Namespace **`kiali-demo`**, labelled `istio-injection=enabled`. Every pod shows `2/2`: the application container plus its `istio-proxy` sidecar proxy (Envoy).

  | Workload | What it is |
  | --- | --- |
  | `notification-service-v1` | Deployment behind the Service `notification-service` on port `80`; it answers `["EMAIL"]` |
  | `tester` | Client pod with `curl`; send test requests from here |

- **No traffic and no Istio routing objects at startup.** The Kiali graph is empty until you send requests.

To open Kiali in a browser, forward its port with `kubectl -n istio-system port-forward svc/kiali 20001:20001`, then open `http://localhost:20001`. Whether that works depends on how you are connected to the playground; every task below also has a command-line form.

## Helpers

Paste these once in each new terminal. `start_load` starts a background loop in the `tester` pod that sends five `POST` requests a second to `notification-service`. `stop_load` stops it. `show_codes` counts the response-code series in the `tester` pod's proxy metrics. `show_mtls` counts the `connection_security_policy` values in the destination's proxy metrics.

```sh
start_load() {
  kubectl -n kiali-demo exec deploy/tester -- sh -c \
    'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.2; done" >/dev/null 2>&1 &'
}
stop_load() {
  kubectl -n kiali-demo exec deploy/tester -- pkill -f 'while true' || true
}
show_codes() {
  kubectl -n kiali-demo exec deploy/tester -c istio-proxy -- \
    pilot-agent request GET stats/prometheus \
    | grep istio_requests_total | grep -o 'response_code="[0-9]*"' | sort | uniq -c
}
show_mtls() {
  kubectl -n kiali-demo exec deploy/notification-service-v1 -c istio-proxy -- \
    pilot-agent request GET stats/prometheus | grep istio_requests_total \
    | grep -o 'connection_security_policy="[^"]*"' | sort | uniq -c
}
```

Use them like this: `start_load`, `show_codes`, `show_mtls`, `stop_load`.

## Practice tasks

- Look at the graph with no traffic, then run `start_load`. Note how long the first edge takes to appear, and how long it stays after `stop_load`.
- Write a `VirtualService` for `notification-service` that aborts 30% of requests with a `500`. Watch the edge change colour, then compare the share Kiali shows with the output of `show_codes`.
- Write a `VirtualService` that names a gateway and a subset that do not exist. Find it in the Istio Config view, then confirm the same messages with `istioctl analyze -n kiali-demo`.
- Remove the injection label with `kubectl label namespace kiali-demo istio-injection-`, restart the Deployments with `kubectl -n kiali-demo rollout restart deployment`, and watch the workloads vanish from the graph while they stay in the Workloads list. Put the label back with `kubectl label namespace kiali-demo istio-injection=enabled` and restart again.
- Turn on the Security display option and confirm the padlock with `show_mtls`. Then read the same label in the `tester` pod's proxy metrics and explain why it says `unknown`.
