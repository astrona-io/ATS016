# Task: One Workload Vanished From The Mesh

**Time:** about 15 minutes · **Weight:** Troubleshooting the Mesh Control Plane

## Scenario

A platform change went out overnight. This morning, `istioctl proxy-status`
lists fewer proxies than the namespace `proxysync-demo` has workloads:

```sh
istioctl proxy-status | grep proxysync-demo
```

The missing workload is `Running`, its Service has endpoints, and requests to it
succeed. A security review has also flagged that the mesh policies written for
this namespace "do not appear to apply to everything".

## Your task

In the namespace `proxysync-demo`:

1. Identify which workload is missing from `proxy-status`, and establish which
   of the three possible causes applies — no sidecar, no connectivity to
   `istiod`, or no control plane.
2. Fix the cause so the workload rejoins the mesh.
3. Confirm the workload is genuinely connected, not merely restarted.

## Constraints

- Do not edit `istiod`, its webhooks, or anything in `istio-system`. The control
  plane is healthy.
- Do not delete the Deployment or the Service.
- The fix must survive a future pod replacement — a one-off manual edit to a
  single pod is not acceptable.

## Done when

- Every workload in `proxysync-demo` appears in `istioctl proxy-status` and is
  `SYNCED` on `CDS`, `LDS`, `EDS` and `RDS`.
- The `notification-service` pod reports two containers, one of them
  `istio-proxy`.
- A `POST` from the `tester` pod still returns `200`.
