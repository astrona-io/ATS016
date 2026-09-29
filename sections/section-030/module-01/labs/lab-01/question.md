# Task: The Mesh Works And Nothing Can Change

**Time:** about 20 minutes · **Weight:** Troubleshooting the Mesh Control Plane

## Scenario

An on-call engineer reports that `cphealth-demo` "looks completely fine" —
traffic flows, pods are `Running`, dashboards are green:

```sh
kubectl -n cphealth-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

They also report that a `VirtualService` they applied earlier "did nothing", and
that a colleague's deployment into the namespace has been stuck for an hour.

## Your task

1. Establish why configuration changes have stopped taking effect, and restore
   the component responsible.
2. Find the object that was stored but will never be served, using the two
   places that record it. `kubectl get` and `kubectl describe` will not tell you.
3. Leave the namespace in a state where every proxy is synchronised and traffic
   still returns `200`.

## Constraints

- Do not delete or recreate the `notification-service-v1` Deployment, the
  Service or the `tester` pod.
- Do not uninstall or reinstall Istio. The control plane needs restoring, not
  replacing.
- The invalid object may be **removed or corrected** — but no object may be left
  in the namespace whose route weights do not sum to 100.

## Done when

- `istiod` is `Running` and ready.
- No `VirtualService` in `cphealth-demo` has route weights that fail to sum
  to 100.
- `istioctl proxy-status` shows every proxy in `cphealth-demo` `SYNCED`, and a
  `POST` from `tester` returns `200`.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Common problems: network issues](https://istio.io/latest/docs/ops/common-problems/) — the catalogue of 503 causes and how to tell them apart
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
