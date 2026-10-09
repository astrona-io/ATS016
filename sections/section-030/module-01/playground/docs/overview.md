# Overview: Check Control Plane Health (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the starting workloads, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. `istiod` is Istio's control plane: it sends configuration and certificates to every sidecar proxy, and it serves the injection and validation webhooks.
- Namespace **`cphealth-demo`**, labelled `istio-injection=enabled`. Every pod shows `2/2`: the application container plus its `istio-proxy` sidecar proxy (Envoy).

  | Workload | What it is |
  | --- | --- |
  | `notification-service-v1` | Deployment behind the Service `notification-service` on port `80`; it answers `["EMAIL"]` |
  | `tester` | Client pod with `curl`; send test requests from here |

- A **healthy control plane**. Nothing is broken at the start. The playground exists so you can break `istiod` yourself and watch which half of the mesh notices.

Scaling `istiod` to zero here is safe, because the cluster is yours and you can throw it away. The same command on a shared cluster stops injection, certificate issuing and every configuration change for every team.

## Helpers

Paste these once in each new terminal. `send_request` sends one `POST` to `notification-service` from the `tester` pod and prints the status code. `show_push_counters` prints the push, reject and internal error counters from `istiod`'s metrics on port `15014`.

```sh
send_request() {
  kubectl -n cphealth-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
}
show_push_counters() {
  kubectl -n istio-system exec deploy/istiod -- \
    curl -s localhost:15014/metrics | grep -E '^pilot_(xds_pushes|total_xds_internal_errors|total_xds_rejects)'
}
```

Use them like this: `send_request`, `show_push_counters`.

## Practice tasks

- Run `show_push_counters`, add a label to the Service with `kubectl -n cphealth-demo label service notification-service test=one`, and run it again. Which `type` values went up?
- Scale `istiod` to zero and apply any `VirtualService`. Read the error and name the webhook and the `failurePolicy` that produced it. Scale `istiod` back to one replica.
- Set the injection webhook's `failurePolicy` to `Ignore` with `kubectl edit mutatingwebhookconfiguration istio-sidecar-injector`, scale `istiod` to zero, and restart `notification-service-v1`. Compare the new pod's `READY` column with the `Fail` behaviour, then undo both changes and restart the Deployment again.
- Lower `istiod`'s memory limit with `kubectl -n istio-system set resources deploy istiod --limits=memory=64Mi` and watch the restart count and the last termination reason while `send_request` keeps returning `200`. Undo it with `kubectl -n istio-system rollout undo deploy istiod`.
