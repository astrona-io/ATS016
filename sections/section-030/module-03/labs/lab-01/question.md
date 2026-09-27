# Task: Bring An Exempt Workload Back Into The Mesh

**Time:** about 15 minutes · **Weight:** Troubleshooting the Mesh Control Plane

## Scenario

A security review of `noinject-demo` found that the namespace's mesh policies
"apply to everything except `reporting-service`". Nobody wrote an exception for
it, and the namespace is labelled for injection:

```sh
kubectl get ns noinject-demo --show-labels
kubectl -n noinject-demo get pods
```

`reporting-service` is `Running`, ready, and serving requests.

## Your task

In the namespace `noinject-demo`:

1. Confirm which workload is outside the mesh, using two independent checks.
2. Work the injection checklist in order — namespace label, pod template label,
   pod age, webhook health — and identify the actual cause.
3. Fix it so `reporting-service` joins the mesh, and confirm it connected.

## Constraints

- Do not change the namespace labels. They are already correct, and changing
  them would affect the other workloads.
- Do not edit anything in `istio-system`.
- Do not delete and recreate the Deployment from scratch — edit what is wrong.
- `reporting-service` must still serve traffic afterwards. A workload that joins
  the mesh and stops answering has not been fixed.

## Done when

- `reporting-service` pods report two containers, one of them `istio-proxy`.
- The pod template no longer carries a `sidecar.istio.io/inject` opt-out.
- `reporting-service` appears in `istioctl proxy-status`, and a request to it
  from the `tester` pod returns `200`.
