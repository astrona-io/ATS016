# Question

Solve this question on: `terminal`

**Time:** about 20 minutes · **Exam topic:** Troubleshooting the Mesh Data Plane

## Scenario

Every request between the two workloads in the namespace `mtlsfail-demo` returns `503`. Both pods are `2/2 Running`. The destination's application log is empty, and so, the on-call engineer reports, is its **proxy** log.

```sh
kubectl -n mtlsfail-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

The security team set this namespace to `STRICT` mutual TLS (mTLS) last week, and will not accept a rollback. With mTLS, both sidecar proxies present a certificate, so the connection is encrypted and both identities are checked.

## Your task

In the namespace `mtlsfail-demo`:

1. Read the access log on **both** proxies and write down the signature: the response flag, whether an upstream address is present, and which side logged nothing.
2. Find out what each end of the connection is configured to do. Read the *effective* mTLS mode of the destination, not a single object.
3. Fix the mismatch, and prove the traffic is **encrypted**, not just working.

## Constraints

- **The server must stay `STRICT`.** Relaxing the `PeerAuthentication` to `PERMISSIVE` or `DISABLE` is marked wrong: it makes the error disappear by accepting plain text from every caller.
- Do not delete the `DestinationRule` `notification`. Only its TLS setting is wrong.
- Do not change the Deployments, the Service or the `tester` pod.

## Done when

- A `POST` from `tester` to `http://notification-service/notify` returns `200`.
- The `PeerAuthentication` is still `STRICT`, the `DestinationRule` `notification` still exists, and it no longer sets `tls.mode: DISABLE`.
- The destination proxy's metrics report `connection_security_policy="mutual_tls"` for the traffic, and no plain-text (`none`) traffic.
