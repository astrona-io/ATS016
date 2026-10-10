# Question

Solve this question on: `terminal`

**Time:** about 15 minutes · **Exam topic:** Troubleshooting the Mesh Control Plane

## Scenario

A security review of the namespace `noinject-demo` found that its mesh policies "apply to everything except `reporting-service`". Nobody wrote an exception for it, and the namespace is labelled for injection:

```sh
kubectl get ns noinject-demo --show-labels
kubectl -n noinject-demo get pods
```

`reporting-service` is `Running`, ready, and serving requests.

## Your task

In the namespace `noinject-demo`:

1. Confirm which workload is outside the mesh, using two independent checks.
2. Work the injection checklist in order (namespace label, pod template label, pod age, webhook health) and find the actual cause.
3. Fix it so `reporting-service` joins the mesh, and confirm it connected.

## Constraints

- Do not change the namespace labels. They are already correct, and changing them would affect the other workloads.
- Do not edit anything in `istio-system`.
- Do not delete and recreate the Deployment from scratch. Edit what is wrong.
- `reporting-service` must still serve traffic afterwards. A workload that joins the mesh and stops answering has not been fixed.

## Done when

- `reporting-service` pods carry the `istio-proxy` sidecar.
- The pod template no longer carries a `sidecar.istio.io/inject: "false"` opt-out, and the namespace label is still `istio-injection=enabled`.
- `reporting-service` appears in `istioctl proxy-status`, no xDS type in `istioctl proxy-status -v 1` is `STALE` or `ERROR`, and a request to `http://reporting-service/` from the `tester` pod returns `200`.
