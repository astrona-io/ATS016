# Solution: Diagnose Two Failures From The Logs Alone

Two faults stacked in the same request path. The transport-level one fails
first, so the authorization one is invisible until it is cleared. That ordering
is the skill this capstone tests.

## Step 1 — The first signature

```sh
kubectl -n logcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n logcapstone-demo logs deploy/tester -c istio-proxy --tail=3
echo '--- destination ---'
kubectl -n logcapstone-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

```text
503
[...] "POST /notify HTTP/1.1" 503 UF upstream_reset_before_response_started{connection_termination} - "-" ... "10.244.0.12:8084" outbound|80||notification-service...
--- destination ---
```

Four observations, read together:

| Observation | Means |
| --- | --- |
| flag `UF` | the connection could not be established |
| `upstream_reset_before_response_started` | terminated before any response began |
| upstream host is an **address** | the destination was found and reached |
| destination logged **nothing** | the request never became a request there |

An access log line is written when a *request* completes. A handshake rejected
at the transport layer happens below HTTP, so there is nothing to log. The
silence locates the failure precisely.

## Step 2 — Rule out the look-alike

The same signature appears when an **unmeshed** caller talks to a `STRICT`
workload:

```sh
kubectl -n logcapstone-demo get pods
istioctl proxy-status | grep logcapstone-demo
```

Both `2/2`, both listed. The caller is in the mesh, so this is a configuration
mismatch, not a missing sidecar — and the fix is different for each.

## Step 3 — Read both ends, fix the client

```sh
export POD=$(kubectl -n logcapstone-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
istioctl x describe pod $POD -n logcapstone-demo | grep -i -A2 'Effective PeerAuthentication'
kubectl -n logcapstone-demo get destinationrule -o yaml | grep -A3 'tls:'
```

```text
   Workload mTLS mode: STRICT
      tls:
        mode: DISABLE
```

Server requires mTLS; client is told to send plaintext. `STRICT` is the
documented intent and the task forbids relaxing it, so the client is what is
wrong. Remove **only** the TLS override — Istio's default for sidecar-to-sidecar
traffic is already mesh mTLS:

```sh
kubectl -n logcapstone-demo patch destinationrule notification --type json \
  -p '[{"op":"remove","path":"/spec/trafficPolicy/tls"}]'
kubectl -n logcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

```text
403
```

The `503` is gone and a **new** failure is exposed. This is the moment the
capstone is built around: a fix that changes the symptom is progress, not
completion.

```sh
astrona submit
```

## Step 4 — The second signature

```sh
kubectl -n logcapstone-demo logs deploy/tester -c istio-proxy --tail=1
echo '--- destination ---'
kubectl -n logcapstone-demo logs deploy/notification-service-v1 -c istio-proxy --tail=1
```

```text
[...] "POST /notify HTTP/1.1" 403 - via_upstream - ... outbound|80||notification-service...
--- destination ---
[...] "POST /notify HTTP/1.1" 403 - rbac_access_denied_matched_policy[ns[logcapstone-demo]-policy[notification-allow]-rule[0]] ... inbound|8084||
```

Everything has changed:

- **Both** proxies logged, so the request crossed the network — the handshake
  now succeeds.
- Both show flag `-`: at the connection level nothing went wrong.
- Only the destination's `RESPONSE_CODE_DETAILS` explains the refusal, naming
  the namespace, the policy and the rule index.

A flag of `-` on both sides with a `403` in the middle is a failure the flag
taxonomy cannot explain. The details field on the **right** proxy can.

## Step 5 — Fix the policy without widening it

```sh
kubectl -n logcapstone-demo get authorizationpolicy notification-allow \
  -o jsonpath='{.spec.rules}{"\n"}'
```

```text
[{"to":[{"operation":{"methods":["PUT"]}}]}]
```

The policy permits `PUT`; the documented intent is `POST`. And an `ALLOW` policy
**forbids everything it does not name**, which is why `POST` was denied without
being mentioned anywhere:

```sh
kubectl -n logcapstone-demo patch authorizationpolicy notification-allow --type json \
  -p '[{"op":"replace","path":"/spec/rules/0/to/0/operation/methods","value":["POST"]}]'
```

Replacing `PUT` with `POST` — not adding to it — keeps the "refuses every other
method" half of the intent true.

## Step 6 — Prove all four outcomes

```sh
for M in POST GET; do
  kubectl -n logcapstone-demo exec deploy/tester -- \
    curl -s -o /dev/null -w "$M %{http_code}\n" -X $M http://notification-service/notify
done
kubectl -n logcapstone-demo get peerauthentication default -o jsonpath='{.spec.mtls.mode}{"\n"}'
kubectl -n logcapstone-demo exec deploy/notification-service-v1 -c istio-proxy -- \
  pilot-agent request GET stats/prometheus | grep istio_requests_total \
  | grep -o 'connection_security_policy="[^"]*"' | sort | uniq -c
```

```text
POST 200
GET 403
STRICT
   6 connection_security_policy="mutual_tls"
```

`GET 403` proves the policy is enforcing rather than absent. `mutual_tls` proves
the traffic is encrypted rather than merely working — a `200` alone would also
appear if somebody had set the server to `PERMISSIVE` and left the client
sending plaintext.

```sh
astrona submit
```

## The two failures side by side

| | Fault 1 | Fault 2 |
| --- | --- | --- |
| Status | `503` | `403` |
| Flag | `UF` | `-` on both sides |
| Upstream host | an address | an address |
| Destination logged | **nothing** | yes, with `rbac_access_denied…` |
| Layer | transport (handshake) | HTTP (authorization) |
| Fix | client `DestinationRule` | destination `AuthorizationPolicy` |

## Common mistakes

- Relaxing the `PeerAuthentication` to make the `503` go away. It hides a client
  misconfiguration and weakens security for every caller.
- Looking only at the destination during fault 1 — its log is empty, and that is
  the clue.
- Looking only at the client during fault 2 — its line is unremarkable.
- Stopping at the first fix because the error changed. A new symptom means the
  first fault is cleared, not that the system is healthy.
- Adding `POST` to the method list instead of replacing `PUT`, leaving a method
  permitted that the intent never included.
- Trusting a `200` as proof of encryption.

## Practice variations

- Invert fault 1: set the server to `DISABLE` and the client to `ISTIO_MUTUAL`,
  then read the signature.
- Annotate the `AuthorizationPolicy` with `istio.io/dry-run: "true"` and watch
  the decision move from `enforced` to `shadow` in the `rbac` log.
- Remove the sidecar from the client and reproduce fault 1's signature with a
  different root cause.

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
