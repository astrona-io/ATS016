# Question

Solve this question on: `terminal`

**Time:** about 15 minutes · **Exam topic:** Troubleshooting Configuration

## Scenario

`GET` requests from the `tester` pod to `notification-service` in the namespace `describe-demo` return `403`. The platform team will investigate, but they have no access to this cluster. They ask for an `istioctl bug-report` archive and set two conditions: it must hold the sidecar proxy of the `notification-service` workload and the control plane, and nothing else. A second namespace, `noise-demo`, also runs pods with sidecar proxies, and the platform team must not receive data about them.

```sh
kubectl -n describe-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X GET http://notification-service/notify
```

## Your task

1. Capture an `istioctl bug-report` archive that holds proxy data for the `notification-service-v1` Deployment in `describe-demo`, and data for `istiod` in `istio-system`.
2. Write the archive to the folder `/tmp/ats-016-bug-report/`, so the file is `/tmp/ats-016-bug-report/bug-report.tar.gz`.

## Constraints

- No other proxy may be in the archive: not the `tester` pod in `describe-demo`, not any pod in `noise-demo`, and not the ingress or egress gateway in `istio-system`.
- Do not use `--full-secrets`.
- Do not restart, scale or delete any pod, and do not change any Istio object. This task is about capturing evidence, not fixing the `403`.

## Done when

- `/tmp/ats-016-bug-report/bug-report.tar.gz` exists and `tar tzf` can list it.
- The archive holds the configuration dump of the running `notification-service-v1` pod, under `bug-report/proxies/describe-demo/<pod>/`.
- The archive holds `istiod` data, under `bug-report/istio/istio-system/<istiod pod>/`.
- The only pod under `bug-report/proxies/` is the `notification-service-v1` pod.
