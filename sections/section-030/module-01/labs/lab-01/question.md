# Question

Solve this question on: `terminal`

**Time:** about 20 minutes · **Weight:** Troubleshooting the Mesh Control Plane

## Scenario

Astronaut, an on-call engineer reports that the planet (namespace) `cphealth-demo` "looks completely fine". Traffic flows, pods are `Running`, and dashboards are green:

```sh
kubectl -n cphealth-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

They also report two other things. A `VirtualService` they applied earlier "did nothing". And a colleague's deployment into the namespace has been stuck for an hour.

## Your task

1. Find out why configuration changes have stopped taking effect, and restore the component responsible.
2. Find the object that was stored but will never be served, using the two places that record it. `kubectl get` and `kubectl describe` will not tell you.
3. Leave the namespace in a state where every proxy is synchronised and traffic still returns `200`.

## Constraints

- Do not delete or recreate the `notification-service-v1` Deployment, the Service or the `tester` pod.
- Do not uninstall or reinstall Istio. The control plane needs restoring, not replacing.
- You may **remove or correct** the invalid object, but no object may be left in the namespace whose route weights do not add up to 100.

## Done when

- `istiod` has at least one ready replica, and `istioctl proxy-status` can reach it.
- No `VirtualService` in `cphealth-demo` has route weights that fail to add up to 100, and `istioctl analyze -n cphealth-demo` reports no `Error`.
- `istioctl proxy-status` shows at least two proxies from `cphealth-demo`, none of them `STALE`, and a `POST` from `tester` to `http://notification-service/notify` returns `200`.
