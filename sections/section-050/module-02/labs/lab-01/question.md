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
