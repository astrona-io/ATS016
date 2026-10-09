# Question

Solve this question on: `terminal`

**Time:** about 15 minutes · **Exam topic:** Troubleshooting Configuration

## Scenario

Astronaut, a colleague deployed `notification-service` on the planet (namespace) `analyze-demo` and applied some Istio routing alongside it. Every `kubectl apply` succeeded. `kubectl get` lists all the objects. Nothing reports an error.

Yet requests to the service return `503`:

```sh
kubectl -n analyze-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

## Your task

In the namespace `analyze-demo`:

1. Find every configuration problem with the tool that reads the configuration the way `istiod` does. Note each message's code and severity.
2. Fix the problems so that analysis of the namespace is completely clean: no `Error` and no `Warning`.
3. Restore traffic: a `POST` to `http://notification-service/notify` from the `tester` pod must return `200`.

## Constraints

- **Route only to subsets that exist and that match running pods.** Do not create a subset whose labels select no pod. That swaps one failure for a quieter one, and it is graded as wrong.
- Do not delete the `DestinationRule`.
- Do not scale, restart or change the `notification-service-v1` Deployment, the Service, or the `tester` pod. The workloads are healthy; the configuration is not.
- Leave the namespace labelled for injection.

## Done when

- `istioctl analyze -n analyze-demo` reports no validation issues.
- Ten `POST` requests in a row from `tester` all return `200`.
- Every subset named by a route is defined by the `DestinationRule` and selects at least one running pod.
