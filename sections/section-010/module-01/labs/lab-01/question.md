# Task: Find And Fix The Configuration Errors In `analyze-demo`

**Time:** about 15 minutes · **Weight:** Troubleshooting Configuration

## Scenario

A colleague deployed `notification-service` into the namespace `analyze-demo`
and applied some Istio routing alongside it. Every `kubectl apply` succeeded.
`kubectl get` lists all the objects. Nothing reports an error.

Requests to the service return `503`.

```sh
kubectl -n analyze-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

## Your task

In the namespace `analyze-demo`:

1. Identify every configuration problem, using the tool that reads the
   configuration the way `istiod` does. Note each message's code and severity.
2. Fix every `Error` so that analysis of the namespace is completely clean.
3. Restore traffic: a `POST` to `http://notification-service/notify` from the
   `tester` pod must return `200`.

## Constraints

- **Route only to subsets that exist and that match running pods.** Do not
  create a subset whose labels select no pod — that trades one failure for a
  quieter one and will be marked wrong.
- Do not delete the `DestinationRule`.
- Do not scale, restart or modify the `notification-service-v1` Deployment, the
  Service, or the `tester` pod. The workloads are healthy; the configuration is
  not.
- Leave the namespace labelled for injection.

## Done when

- `istioctl analyze -n analyze-demo` reports no validation issues.
- Ten consecutive `POST` requests from `tester` all return `200`.
- Every subset named by a route is defined by the `DestinationRule` and selects
  at least one running pod.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Envoy access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — turning logging on and reading the response flags
- [Common problems: network issues](https://istio.io/latest/docs/ops/common-problems/) — the catalogue of 503 causes and how to tell them apart
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
