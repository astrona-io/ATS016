# Question

Solve this question on: `terminal`

**Time:** about 15 minutes · **Weight:** Troubleshooting the Mesh Control Plane

## Scenario

Astronaut, a platform change went out overnight. This morning, mission control's roll call, `istioctl proxy-status`, lists fewer proxies than the planet (namespace) `proxysync-demo` has workloads:

```sh
istioctl proxy-status | grep proxysync-demo
```

The missing workload is `Running`, its Service has endpoints, and requests to it succeed. A security review has also flagged that the mesh policies written for this namespace "do not appear to apply to everything".

## Your task

In the namespace `proxysync-demo`:

1. Find which workload is missing from `istioctl proxy-status`, and decide which of the three possible causes applies: no sidecar, no connection to `istiod`, or no control plane.
2. Fix the cause so the workload rejoins the mesh.
3. Confirm the workload is really connected, not just restarted.

## Constraints

- Do not edit `istiod`, its webhooks, or anything in `istio-system`. The control plane is healthy.
- Do not delete the Deployment or the Service.
- The fix must survive a future pod replacement. A one-off manual edit to a single pod is not accepted.

## Done when

- Every running pod in `proxysync-demo` appears in `istioctl proxy-status`, and no row is `STALE`.
- The `notification-service` pod carries the `istio-proxy` sidecar, and the namespace carries an injection label (`istio-injection` or `istio.io/rev`), so new pods get one too.
- A `POST` from the `tester` pod to `http://notification-service/notify` still returns `200`.
