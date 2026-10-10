# Question

Solve this question on: `terminal`

**Time:** about 40 minutes · **Exam topic:** Troubleshooting the Mesh Control Plane

## Scenario

A platform migration left three workloads in an inconsistent state across two namespaces:

- `orders-service` in `cpcapstone-demo`
- `payments-service` in `cpcapstone-demo`
- `billing-service` in `cpcapstone-legacy`

`istioctl proxy-status` lists fewer proxies than there are workloads. Requests to `payments-service` get a `301` redirect to `/v2` that nobody configured on purpose. The control plane itself is running normally: this is not one outage with three symptoms.

## Your task

1. For **each** workload, find out whether it is in the mesh and synchronised. Check whether `istio-proxy` is in the pod (the `READY` column, or the init containers) and use `istioctl proxy-status`, not assumptions.
2. Diagnose and fix each of the three faults. They have three different causes and three different fixes.
3. Find the object that was stored without validation and causes the redirect. `kubectl get` and `kubectl describe` will not show what is wrong with it.

## Constraints

- Do not uninstall or reinstall Istio, and do not edit `istiod`'s Deployment.
- Do not delete any of the three Deployments or their Services.
- `cpcapstone-legacy` must end up served by a control plane revision that actually exists.
- You may **remove or correct** the invalid `VirtualService`, but no HTTP rule may remain with both a `redirect` and a `route`.

## Done when

- `orders-service`, `payments-service`, `billing-service` and `tester` all appear in `istioctl proxy-status`, and no xDS type in `istioctl proxy-status -v 1` is `STALE` or `ERROR`.
- `orders-service` pods carry the `istio-proxy` sidecar, and its pod template no longer carries the `sidecar.istio.io/inject: "false"` opt-out.
- `billing-service` pods carry the `istio-proxy` sidecar, and `cpcapstone-legacy` carries an injection label that names an installed revision (or `istio-injection=enabled`).
- No HTTP rule in `cpcapstone-demo` has both a `redirect` and a `route`, and a request from `tester` to `http://payments-service/get` returns `200`.
