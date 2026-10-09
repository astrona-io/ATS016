# Overview: Debug A Workload With No Sidecar (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the starting workloads, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. `istiod` serves the injection webhook that adds the `istio-proxy` sidecar proxy to new pods.
- Namespace **`noinject-demo`**, labelled `istio-injection=enabled`:

  | Workload | What it is |
  | --- | --- |
  | `notification-service-v1` | A workload in the mesh, behind the Service `notification-service`, for comparison |
  | `reporting-service` | An HTTP echo server (go-httpbin) behind the Service `reporting-service` on port `80`. It is **not** in the mesh; the reason is in its pod template, so find it with the checklist |
  | `tester` | Client pod with `curl`; send test requests from here |

## Helpers

Paste these once in each new terminal. `show_containers` lists every pod in `noinject-demo` with its init containers and containers, so a native sidecar is visible too. `call_reporting` sends one request to `reporting-service` from the `tester` pod and prints the status code.

```sh
show_containers() {
  kubectl -n noinject-demo get pods \
    -o custom-columns='POD:.metadata.name,INIT:.spec.initContainers[*].name,CONTAINERS:.spec.containers[*].name'
}
call_reporting() {
  kubectl -n noinject-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' http://reporting-service/
}
```

Use them like this: `show_containers`, `call_reporting`.

## Practice tasks

- Work the checklist in order on `reporting-service` before you read its full YAML, and note which step ruled out which cause.
- Fix it, then break it a different way: remove the namespace label, restart both Deployments, and confirm both workloads leave the mesh.
- Add the namespace label back but do **not** restart. Confirm that nothing changes, then restart and confirm that it does.
- Label the namespace `istio.io/rev=nonexistent` while `istio-injection=enabled` is still there, restart `notification-service-v1`, and use the `ISTIOD` column of `istioctl proxy-status` to work out which label won. Then remove `istio-injection` and restart again.
- Set the injection webhook's `failurePolicy` to `Ignore`, scale `istiod` to zero, and restart `notification-service-v1`. Look at how quiet the result is, then undo both changes.
