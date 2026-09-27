# Capstone: Diagnose Two Failures From The Logs Alone

**Time:** about 35 minutes · **Weight:** Troubleshooting the Mesh Data Plane
**Covers:** modules 1–2 (access logs and response flags, mTLS mismatch)

## Scenario

Nothing in `logcapstone-demo` works. The intent, per the team's documentation,
is:

- all traffic between workloads is **encrypted**;
- `notification-service` accepts `POST` and refuses every other method.

Both pods are `2/2 Running`. The application logs are empty.

There are **two** independent faults, and the second is hidden behind the first:
until you fix one, you cannot observe the other. Work them in order.

## Your task

1. Read the access log on **both** proxies and record the first signature — the
   response flag, whether an upstream address is present, and which side logged
   nothing.
2. Fix the first fault, then repeat step 1. The signature will have changed;
   read the new one, including `RESPONSE_CODE_DETAILS`.
3. Fix the second fault so the documented intent holds.

## Constraints

- **The `PeerAuthentication` must remain `STRICT`.** Relaxing it makes the first
  symptom disappear by accepting plaintext, and will be marked wrong.
- Do not delete the `DestinationRule` — it carries a connection pool setting the
  platform team needs. Change only what is wrong.
- Do not delete the `AuthorizationPolicy`, and do not widen it to allow every
  method.
- Do not modify the Deployments, the Service or the `tester` pod.

## Done when

- A `POST` from `tester` returns `200`.
- A `GET` from `tester` returns `403`.
- The `PeerAuthentication` is still `STRICT` and the client no longer disables
  TLS.
- The destination proxy reports `connection_security_policy="mutual_tls"`.
