# Task: A 503 Where The Destination Log Is Empty

**Time:** about 20 minutes · **Weight:** Troubleshooting the Mesh Data Plane

## Scenario

Every request between the two workloads in `mtlsfail-demo` returns `503`. Both
pods are `2/2 Running`. The destination's application log is empty — and so, the
on-call engineer reports, is its **proxy** log.

```sh
kubectl -n mtlsfail-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

The security team tightened this namespace to `STRICT` mTLS last week and will
not accept a rollback.

## Your task

In the namespace `mtlsfail-demo`:

1. Read the access log on **both** proxies and record the signature — the
   response flag, whether an upstream address is present, and which side logged
   nothing.
2. Establish what each end of the connection is configured to do. Read the
   *effective* mTLS mode, not a single object.
3. Fix the mismatch, and prove the traffic is **encrypted**, not merely working.

## Constraints

- **The server must remain `STRICT`.** Relaxing `PeerAuthentication` to
  `PERMISSIVE` or `DISABLE` will be marked wrong — it makes the error disappear
  by accepting plaintext from every caller.
- Do not delete the `DestinationRule`. It carries a connection pool setting the
  platform team needs; only the TLS part is wrong.
- Do not modify the Deployments, the Service or the `tester` pod.

## Done when

- A `POST` from `tester` returns `200`.
- The `PeerAuthentication` is still `STRICT`.
- The destination proxy's metrics report
  `connection_security_policy="mutual_tls"` for the traffic.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Describing pod configuration](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-describe/) — what the mesh is applying to one workload
- [Envoy access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — turning logging on and reading the response flags
- [Common problems: network issues](https://istio.io/latest/docs/ops/common-problems/) — the catalogue of 503 causes and how to tell them apart
- [Authorization policy](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — the object whose deny you may be debugging
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
