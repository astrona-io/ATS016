# Capstone: Three Workloads, Three Different Control Plane Faults

**Time:** about 40 minutes · **Weight:** Troubleshooting the Mesh Control Plane
**Covers:** modules 1–3 (istiod health, config sync, sidecar injection)

## Scenario

A platform migration left three workloads in an inconsistent state across two
namespaces:

- `orders-service` in `cpcapstone-demo`
- `payments-service` in `cpcapstone-demo`
- `billing-service` in `cpcapstone-legacy`

`istioctl proxy-status` lists fewer proxies than there are workloads. A
`VirtualService` applied for `payments-service` "did nothing". The control plane
itself is running normally — this is not a single outage with three symptoms.

## Your task

1. Determine, for **each** workload, whether it is in the mesh and synchronised,
   using the container count and `istioctl proxy-status` rather than assumptions.
2. Diagnose and fix each of the three faults. They have three different causes
   and three different fixes.
3. Find the object that was stored but will never be served. `kubectl get` and
   `kubectl describe` will not reveal it.

## Constraints

- Do not uninstall or reinstall Istio, and do not edit `istiod`'s Deployment.
- Do not delete any of the three Deployments or their Services.
- `cpcapstone-legacy` must end up served by a control plane revision that
  actually exists.
- The invalid `VirtualService` may be **removed or corrected**, but nothing may
  remain whose route weights fail to sum to 100.

## Done when

- All three workloads appear in `istioctl proxy-status` and none is `STALE`.
- `orders-service` pods carry an `istio-proxy` container.
- `billing-service` pods carry an `istio-proxy` container, and
  `cpcapstone-legacy` names an installed revision.
- No route weights in `cpcapstone-demo` fail to sum to 100, and a request from
  `tester` to `payments-service` returns `200`.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
- [Sidecar injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) — why a pod came up without a proxy
- [Canary upgrades and revision labels](https://istio.io/latest/docs/setup/upgrade/canary/) — revision labels, and the skew that breaks a data plane
