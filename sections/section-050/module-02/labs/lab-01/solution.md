# Solution: A 503 Where The Destination Log Is Empty

## Step 1 — Read the pair of logs

```sh
kubectl -n mtlsfail-demo logs deploy/tester -c istio-proxy --tail=3
echo '--- destination ---'
kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

```text
[...] "POST /notify HTTP/1.1" 503 UF upstream_reset_before_response_started{connection_termination} - "-" 0 95 3 - ... "10.244.0.12:8084" outbound|80||notification-service...
--- destination ---
```

Four details together are the whole diagnosis:

| Observation | Means |
| --- | --- |
| flag `UF` | upstream connection failure — the proxy could not establish a usable connection |
| details `upstream_reset_before_response_started` | the connection was terminated before any response began |
| upstream host `10.244.0.12:8084` | an **address**, so the destination was found and reached |
| destination logged **nothing** | the request never became a request there |

That last row is evidence, not a gap. An access log line is written when a
*request* completes; a handshake rejected at the transport layer happens one
level below anything HTTP. So the failure is **below HTTP, on the receiving
side** — which distinguishes this from `NC`/`UH`, where the upstream host field
would be `-`.

## Step 2 — Rule out the look-alike first

The same signature appears when an **unmeshed** caller talks to a `STRICT`
workload. Check before touching policy:

```sh
kubectl -n mtlsfail-demo get pods
istioctl proxy-status | grep mtlsfail-demo
```

Both pods are `2/2` and both appear in `proxy-status`. The caller is in the
mesh, so this is a configuration mismatch rather than a missing sidecar.

## Step 3 — Read both ends

```sh
export POD=$(kubectl -n mtlsfail-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
istioctl x describe pod $POD -n mtlsfail-demo | grep -i -A2 'Effective PeerAuthentication'
kubectl -n mtlsfail-demo get destinationrule -o yaml | grep -A3 'tls:'
```

```text
   Workload mTLS mode: STRICT
      tls:
        mode: DISABLE
```

The server requires mTLS; the client is told to send plaintext. Each object is
valid and neither references the other — which is why this survived review.

Use `describe` rather than reading `PeerAuthentication` directly: mesh,
namespace and workload policies resolve narrowest-first and per port, and only
the effective value accounts for that.

## Step 4 — Fix the client, not the server

`STRICT` is the intended posture and the task forbids relaxing it. `tls: DISABLE`
on the client is the mistake — almost always inherited, copied along with a
`DestinationRule` written for something else.

Remove **only** the TLS override. Istio's default for sidecar-to-sidecar traffic
is already mesh mTLS, so deleting the field is better than setting it
explicitly — one less thing to drift:

```sh
kubectl -n mtlsfail-demo patch destinationrule notification --type json \
  -p '[{"op":"remove","path":"/spec/trafficPolicy"}]'
kubectl -n mtlsfail-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

```text
200
```

Setting `tls.mode: ISTIO_MUTUAL` is equally correct. What is *not* correct is
`MUTUAL` — that means "mTLS with certificates I supply" and needs a secret
reference.

```sh
astrona submit
```

## Step 5 — Prove encryption, not just success

A `200` would also appear if somebody had "fixed" this by setting the server to
`PERMISSIVE` and left the client sending plaintext. Those are different outcomes
with identical status codes:

```sh
kubectl -n mtlsfail-demo exec deploy/notification-service-v1 -c istio-proxy -- \
  pilot-agent request GET stats/prometheus | grep istio_requests_total \
  | grep -o 'connection_security_policy="[^"]*"' | sort | uniq -c
```

```text
   4 connection_security_policy="mutual_tls"
```

The label is meaningful on the **destination** — the receiving proxy is the one
that knows how the connection was secured. `none` here would mean working,
unencrypted traffic and a fix applied to the wrong end.

Finally, the log that was empty:

```sh
kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

```text
[...] "POST /notify HTTP/1.1" 200 - via_upstream - ... inbound|8084|| ...
```

Requests are arriving and being served against the `inbound|8084||` cluster.
Their absence was the signature; their presence is the proof.

```sh
astrona submit
```

## Common mistakes

- Relaxing the `PeerAuthentication` to `PERMISSIVE` to make the error go away.
  That hides a client misconfiguration and weakens security for every caller.
- Looking only at the destination. Its log is empty — which is itself the clue.
- Forgetting that an absent `DestinationRule` `tls` block means mesh mTLS by
  default, so *adding* one can only make things worse here.
- Confusing this with an unmeshed caller. Check whether the client has a sidecar
  before editing policy.
- Trusting a `200` as proof of encryption.

## Practice variations

- Invert the mistake: set the server to `DISABLE` and the client to
  `ISTIO_MUTUAL`, then read the log signature.
- Remove the sidecar from the client and reproduce the same `503` with a
  different root cause.
- Set a port-level exception with `portLevelMtls` so one port works and another
  fails.
