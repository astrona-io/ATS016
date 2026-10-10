# Question

Solve this question on: `terminal`

**Time:** about 20 minutes · **Exam topic:** Troubleshooting the Mesh Control Plane

## Scenario

An on-call engineer reports that the namespace `cphealth-demo` "looks completely fine". Traffic flows, pods are `Running`, and dashboards are green:

```sh
kubectl -n cphealth-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

They also report two other things. Changes they apply to the namespace "do nothing". And a colleague's deployment into the namespace has been stuck for an hour. While the control plane was unavailable, someone also applied a `VirtualService` that skipped validation.

## Your task

1. Find out why configuration changes have stopped taking effect, and restore the component responsible.
2. Once the control plane is back, the same request returns `301` instead of `200`. Find the object that was stored without validation and causes it. `kubectl get` and `kubectl describe` will not tell you what is wrong with it.
3. Leave the namespace in a state where every proxy is synchronised and traffic still returns `200`.

## Constraints

- Do not delete or recreate the `notification-service-v1` Deployment, the Service or the `tester` pod.
- Do not uninstall or reinstall Istio. The control plane needs restoring, not replacing.
- You may **remove or correct** the invalid object, but no `VirtualService` may be left in the namespace with an HTTP rule that has both a `redirect` and a `route`.

## Done when

- `istiod` has at least one ready replica, and `istioctl proxy-status` can reach it.
- No `VirtualService` in `cphealth-demo` has an HTTP rule with both a `redirect` and a `route`, and `istioctl analyze -n cphealth-demo` reports no `Error`.
- `istioctl proxy-status` shows at least two proxies from `cphealth-demo`, and no xDS type in `istioctl proxy-status -v 1` is `STALE` or `ERROR`, and a `POST` from `tester` to `http://notification-service/notify` returns `200`.
