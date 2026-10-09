# Overview: Diagnose Configuration Sync With proxy-status (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the starting workloads, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. The `demo` profile also installs an ingress and an egress gateway in `istio-system`, so `istioctl proxy-status` lists them too.
- Namespace **`proxysync-demo`**, labelled `istio-injection=enabled`. Every pod shows `2/2`: the application container plus its `istio-proxy` sidecar proxy (Envoy).

  | Workload | What it is |
  | --- | --- |
  | `notification-service-v1` | Deployment behind the Service `notification-service` on port `80`; it answers `["EMAIL"]` |
  | `tester` | Client pod with `curl`; send test requests from here |

- A **healthy mesh**. Every proxy starts `SYNCED` on every xDS type it uses; making one stop is up to you.

## Helpers

Paste these once in each new terminal. `send_request` sends one `POST` to `notification-service` from the `tester` pod and prints the status code. `show_sync` prints the per-type sync state of every proxy in `proxysync-demo`.

```sh
send_request() {
  kubectl -n proxysync-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
}
show_sync() {
  istioctl proxy-status -v 1 | grep -E '^NAME|proxysync-demo'
}
```

Use them like this: `send_request`, `show_sync`.

## Practice tasks

- Remove the namespace injection label, restart `notification-service-v1`, and watch its row disappear from `show_sync` while `send_request` still returns `200`. Put the label back and restart again.
- Apply any `VirtualService` for `notification-service`, then run `show_sync` several times in a row and try to catch a `STALE` before it settles.
- Run `istioctl proxy-status deploy/tester.proxysync-demo` and read the per-resource comparison.
- Scale `istiod` to zero and see what `istioctl proxy-status` itself does when the control plane it asks is gone. Scale it back to one replica.
- Write a `NetworkPolicy` that allows the `notification-service` pods only UDP port `53` egress, apply it, and restart the Deployment. Check the new pod's `READY` column, its row in `show_sync`, and its `istio-proxy` log. Delete the policy afterwards.
- Compare `istioctl version` with the `VERSION` column of `istioctl proxy-status`.
