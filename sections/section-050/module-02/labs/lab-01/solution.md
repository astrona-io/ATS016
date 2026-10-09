# Solution: A 503 Where The Destination Log Is Empty

The grader checks three things: a `POST` returns `200`; the `PeerAuthentication` is still `STRICT` and the `DestinationRule` `notification` still exists without `tls.mode: DISABLE`; and the destination proxy reports `connection_security_policy="mutual_tls"` with no plain text. This walkthrough finds the mismatch from the logs, fixes the client end, and proves all three.

## Step 1: Read the pair of logs

Read the newest flight log lines (access log) on the client's proxy and on the destination's proxy:

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
| flag `UF` | upstream connection failure: the proxy could not set up a usable connection |
| details `upstream_reset_before_response_started` | the connection was closed before any response began |
| upstream host `10.244.0.12:8084` | an **address**, so the destination was found and reached |
| destination logged **nothing** | the request never became a request there |

The last row is evidence, not a gap. A proxy writes an access log line when a *request* completes. A handshake rejected at the transport layer happens one level below HTTP. So the failure is **below HTTP, on the receiving side**. That separates it from `NC` and `UH`, where the upstream host field would be `-`.

## Step 2: Rule out the look-alike first

The same signature appears when a caller **outside the mesh** talks to a `STRICT` workload. Check that before you touch any policy:

```sh
kubectl -n mtlsfail-demo get pods
istioctl proxy-status | grep mtlsfail-demo
```

Both pods are `2/2` and both appear in `proxy-status`, mission control's roll call. The caller is in the mesh, so this is a configuration mismatch, not a missing sidecar.

## Step 3: Read both ends

Read the destination's effective mTLS mode, then the client's TLS setting:

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

The server requires the handshake; the client is told to send plain text. Each object is valid and neither mentions the other, which is why this survived review.

Use `istioctl x describe pod` instead of reading the `PeerAuthentication` directly. Mesh, namespace and workload policies merge, narrowest first and per port, and only the effective value accounts for that.

## Step 4: Fix the client, not the server

`STRICT` is the intended rule and the task forbids relaxing it. `tls: DISABLE` on the client is the mistake.

Remove the client's traffic policy, which holds only that TLS override. Istio's default for traffic between sidecars is already mesh mTLS, so deleting the setting is better than setting it explicitly: one less thing to drift. The `DestinationRule` itself stays:

```sh
kubectl -n mtlsfail-demo patch destinationrule notification --type json \
  -p '[{"op":"remove","path":"/spec/trafficPolicy"}]'
kubectl -n mtlsfail-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

```text
200
```

Setting `tls.mode: ISTIO_MUTUAL` would also be correct. `MUTUAL` would not: it means "mutual TLS with certificates I supply" and needs a certificate reference.

Submit to see the first checks pass:

```sh
astrona submit -c sections/section-050/module-02/labs/lab-01
```

## Step 5: Prove encryption, not just success

A `200` would also appear if someone had "fixed" this by setting the server to `PERMISSIVE` and left the client sending plain text. Those are different outcomes with the same status code. Ask the destination proxy how the connections were secured:

```sh
kubectl -n mtlsfail-demo exec deploy/notification-service-v1 -c istio-proxy -- \
  pilot-agent request GET stats/prometheus | grep istio_requests_total \
  | grep -o 'connection_security_policy="[^"]*"' | sort | uniq -c
```

```text
   4 connection_security_policy="mutual_tls"
```

The label means something on the **destination**: the receiving proxy is the one that knows how the connection was secured. `none` here would mean working, unencrypted traffic and a fix on the wrong end.

Finally, read the log that was empty:

```sh
kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

```text
[...] "POST /notify HTTP/1.1" 200 - via_upstream - ... inbound|8084|| ...
```

Requests now arrive and are served against the `inbound|8084||` cluster. Their absence was the signature; their presence is the proof.

Submit again. All three checks should pass:

```sh
astrona submit -c sections/section-050/module-02/labs/lab-01
```

## Common mistakes

- Relaxing the `PeerAuthentication` to `PERMISSIVE` to make the error go away. That hides a client misconfiguration and weakens security for every caller.
- Looking only at the destination. Its log is empty, and that emptiness is the clue.
- Forgetting that with no `tls` setting in a `DestinationRule`, the client uses mesh mTLS by default, so *adding* one can only make things worse here.
- Confusing this with a caller outside the mesh. Check whether the client has a sidecar before you edit policy.
- Deleting the `DestinationRule` instead of removing its TLS setting.
- Trusting a `200` as proof of encryption.

## Practice variations

- Invert the mistake: set the server to `DISABLE` and the client to `ISTIO_MUTUAL`, then read the log signature.
- Remove the sidecar from the client and reproduce the same `503` with a different root cause.
- Set a port-level exception with `portLevelMtls` so one port works and another fails.
