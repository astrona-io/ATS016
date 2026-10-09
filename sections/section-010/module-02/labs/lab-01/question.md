# Question

Solve this question on: `terminal`

**Time:** about 15 minutes · **Exam topic:** Troubleshooting Configuration

## Scenario

Astronaut, `notification-service` on the planet (namespace) `describe-demo` is covered by four Istio objects written by three different people. A monitoring team now needs to poll the service with `GET /notify` for a read-only status check. They report that every attempt is refused:

```sh
kubectl -n describe-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X GET http://notification-service/notify
```

Nothing in the application logs explains the refusal.

Separately, a colleague investigating an unrelated issue last week turned up a diagnostic log setting on the `notification-service` proxy and never put it back.

## Your task

In the namespace `describe-demo`:

1. Find which of the four objects refuses the `GET`, using the command that summarises everything that applies to one workload. Do not guess by reading YAML.
2. Change that object so `GET` is allowed **in addition to** `POST`.
3. Find the proxy log scope that was left raised, and return it to its default level, `info`.

## Constraints

- **`POST` must keep working**, and any method that is neither `GET` nor `POST` must still be refused. Do not replace the policy with one that allows everything, and do not delete it.
- **The effective mutual TLS mode for the workload must stay `STRICT`.** Relaxing the `PeerAuthentication` is not a fix for an authorization problem.
- Do not change the Deployment, the Service or the `tester` pod.

## Done when

- `GET` and `POST` to `http://notification-service/notify` both return `200`.
- A `DELETE` to the same path still returns `403`.
- The `PeerAuthentication` is still `STRICT`, and `istioctl x describe pod` reports the workload's effective mutual TLS mode as `STRICT`.
- `istioctl proxy-config log` shows the `rbac` scope of the `notification-service` proxy back at `info`.
