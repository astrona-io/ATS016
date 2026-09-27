# Part 3 — Fixing It, And Proving Encryption

> Prerequisite: [Part 2 — The Signature](./course-02-the-signature.md). Next: [the module landing page](./course.md), then [section 060](../../section-060/module-01/course.md).

Both ends are wrong relative to each other, so "which object is wrong" is a judgement rather than a lookup — and the wrong judgement produces working traffic with no encryption, which is worse than the failure it replaced. This part makes the choice explicit, applies the fix that removes configuration rather than adding it, and then proves the result properly.

## Which end to change

**`STRICT` on the server is almost always the intended setting.** It is what a mesh is for. Relaxing it to `PERMISSIVE` to make an error go away has two costs, and both are larger than they look:

- It weakens the posture for **every** client of that workload, not just the broken one. A single misconfigured caller becomes a reason to accept plaintext from anywhere.
- It converts a loud failure into a silent one. Traffic starts working, unencrypted, and nothing reports it — the state [Part 1](./course-01-two-objects-two-ends.md) described as surviving for a year.

**`tls: DISABLE` on the client is almost always a mistake**, and usually an inherited one — a `tls:` block copied along with a `DestinationRule` written for load balancing or connection pooling.

So the fix goes on the client. Two forms are correct and they are not equal:

| Fix | Effect | Verdict |
| --- | --- | --- |
| set `tls.mode: ISTIO_MUTUAL` | explicitly requests mesh mTLS | correct, and one more setting to keep right |
| **remove the `tls:` block** | Istio's default applies — mesh mTLS | **better** |

Removing it is better for a reason worth generalising: the default is already correct, so pinning it in configuration adds a thing that can drift, be copied, or disagree with a future server change. Delete the override; keep the rest of the `DestinationRule`, which was written for something else entirely.

> [!TIP]
> **Try it — removing the override**
>
> ```sh
> kubectl -n mtlsfail-demo patch destinationrule notification --type json \
>   -p '[{"op":"remove","path":"/spec/trafficPolicy/tls"}]'
> kubectl -n mtlsfail-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
> ```
>
> Expect something like:
>
> ```text
> destinationrule.networking.istio.io/notification patched
> 200
> ```
>
> A JSON Patch `remove` on exactly one path, so the `DestinationRule` still exists and still governs everything it was written for. Istio's default takes over, the client cluster gets Istio's certificates attached, and the handshake succeeds within a second — no restart, because this is a CDS push over the existing xDS stream.

## Working is not encrypted

A `200` proves the handshake succeeded. It would *also* appear if someone had "fixed" this by setting the server to `PERMISSIVE` and left the client sending plaintext. Those are different outcomes with identical status codes, and distinguishing them is not optional on a mesh whose point is encryption.

Istio's telemetry carries the answer. Every request the destination proxy handles increments `istio_requests_total`, labelled with `connection_security_policy`:

| Value | Means |
| --- | --- |
| `mutual_tls` | the connection was mTLS |
| `none` | plaintext |
| `unknown` | reported by a proxy that cannot know — typically the client side |

The label is meaningful on the **destination**, because the receiving proxy is the one that knows how the connection was secured.

> [!TIP]
> **Try it — what the destination says about the connection**
>
> ```sh
> kubectl -n mtlsfail-demo exec deploy/notification-service-v1 -c istio-proxy -- \
>   pilot-agent request GET stats/prometheus \
>   | grep istio_requests_total | grep -o 'connection_security_policy="[^"]*"' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
>    4 connection_security_policy="mutual_tls"
> ```
>
> `mutual_tls` on every counted request. `pilot-agent request GET` reads the sidecar's admin interface from inside the container ([module 010-02 Part 2](../../section-010/module-02/course-02-envoy-log-scopes-at-runtime.md)), which is how you read a proxy's statistics with no Prometheus in the cluster — a technique well beyond this module.
>
> If this had printed `none`, the traffic would be working and unencrypted, and the fix would have been applied to the wrong end.

## The log that was empty

One more confirmation, and it is the most direct of all: the destination proxy should now be logging these requests. Throughout the failure it logged nothing.

> [!TIP]
> **Try it — the log that was empty before**
>
> ```sh
> kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
> ```
>
> Expect something like:
>
> ```text
> [...] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 14 1 1 "-" "curl/8.4.0" "..." "notification-service" "10.244.0.12:8084" inbound|8084|| ...
> ```
>
> Requests are arriving and being served, logged against the `inbound|8084||` cluster. The absence of exactly these lines was the signature in [Part 2](./course-02-the-signature.md); their presence is the cleanest possible proof that the handshake now completes and requests are becoming requests on the far side.

Three confirmations, each answering a different question: the `200` says it works, `connection_security_policy` says it is encrypted, and the destination's log says the request arrived. A fix that cannot produce all three is not finished.

## The variant with no DestinationRule at all

The same `UF` signature appears in a second scenario with a completely different fix: a workload **outside the mesh** calling a `STRICT` workload. With no sidecar, the caller sends plaintext and cannot present a certificate, so the destination rejects the handshake identically.

The tells:

- There is **no client-side access log** to read — the caller has no proxy to write one.
- The calling pod is `1/1`, not `2/2` ([module 030-03](../../section-030/module-03/course.md)).
- The caller does not appear in `istioctl proxy-status`.

The fix is to bring the caller into the mesh, **not** to relax the server. Relaxing the server to `PERMISSIVE` would make it work and would leave the caller permanently outside every policy the mesh enforces — which is the same trade rejected at the start of this part, arrived at from a different direction.

There is a legitimate middle ground worth knowing about: `portLevelMtls` can exempt one specific port from `STRICT` while the rest of the workload stays strict. That is the right tool when something genuinely cannot be meshed — a legacy scraper, an external health check — because it scopes the exception to a port rather than to the whole workload.

## The method

```text
   1. Flag UF + upstream address + silent destination?   → this class of failure
   2. Is the caller in the mesh?  (2/2, proxy-status)
          no  → mesh the caller. Do not touch the server.
          yes → continue
   3. istioctl x describe pod <dest>                     → effective server mode
   4. get destinationrule -o yaml | grep -A3 'tls:'      → what the client sends
   5. Fix the CLIENT: remove the tls block (or ISTIO_MUTUAL)
   6. Prove three ways: 200, connection_security_policy, destination log
```

Step 2 before step 5 is the ordering that matters. Both scenarios present identically on the server; only the caller's own state separates them, and fixing the wrong one produces plaintext traffic that everybody believes is encrypted.

> [!WARNING]
> **Pitfalls in fixing**
>
> - **Relaxing the server to `PERMISSIVE` to make it work.** It removes the failure and the guarantee together, for every client of that workload.
> - **Trusting a `200` as proof of encryption.** Check `connection_security_policy` on the destination; `PERMISSIVE` serves plaintext with a perfectly healthy status code.
> - **Adding `ISTIO_MUTUAL` when removing the block would do.** The default is already correct; an explicit setting is one more thing to drift.
> - **Deleting the whole `DestinationRule`.** It was probably written for load balancing or connection pooling. Remove the `tls:` path only.
> - **Fixing the server when the caller is unmeshed.** Same symptom, different cause; mesh the caller instead, or scope an exemption with `portLevelMtls`.
> - **Stopping at one confirmation.** Working, encrypted and arriving are three separate claims.

> *Fix the end that is wrong about reality — and then prove the traffic is encrypted, because "it works now" is exactly what the wrong fix also produces.*

## Reference

- [Destination rule — ClientTLSSettings](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ClientTLSSettings) — the modes, and what `ISTIO_MUTUAL` supplies automatically.
- [Peer authentication — portLevelMtls](https://istio.io/latest/docs/reference/config/security/peer_authentication/#PeerAuthentication-PortLevelMTLS) — scoping an exemption to one port.
- [Istio standard metrics](https://istio.io/latest/docs/reference/config/metrics/) — `connection_security_policy` and the other labels on `istio_requests_total`.
- [Mutual TLS migration](https://istio.io/latest/docs/tasks/security/authentication/mtls-migration/) — verifying that all traffic is mTLS before tightening a namespace to `STRICT`.
