# Part 2 — The Signature

> Prerequisite: [Part 1 — Two Objects, Two Ends Of One Connection](./course-01-two-objects-two-ends.md). Next: [Part 3 — Fixing It, And Proving Encryption](./course-03-fixing-and-proving-encryption.md).

Part 1 explained why this failure produces a reset connection rather than an error response. This part is the resulting evidence pattern — one flag on one side, nothing on the other — and how to confirm it against the effective policy rather than against a single object.

## The symptom is unremarkable

> [!TIP]
> **Try it — the failure**
>
> ```sh
> kubectl -n mtlsfail-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
> kubectl -n mtlsfail-demo get pods
> ```
>
> Expect something like:
>
> ```text
> 503
> NAME                                      READY   STATUS    RESTARTS   AGE
> notification-service-v1-6c9f8b7d5-x2kqp   2/2     Running   0          7m
> tester-6d9f7b8c5-hj4kz                    2/2     Running   0          7m
> ```
>
> A `503` against a `2/2 Running` destination — byte for byte the starting point of [module 040-02](../../section-040/module-02/course.md), and a completely different cause. Both pods have sidecars, which rules out [module 030-03](../../section-030/module-03/course.md), and nothing has restarted. The status code cannot distinguish this from a missing subset; the next command can.

## The pair of logs

The distinguishing evidence is not one line but a **pair**: read the client's proxy and the destination's proxy for the same request.

> [!TIP]
> **Try it — the signature**
>
> ```sh
> kubectl -n mtlsfail-demo logs deploy/tester -c istio-proxy --tail=3
> echo '--- destination ---'
> kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
> ```
>
> Expect something like:
>
> ```text
> [...] "POST /notify HTTP/1.1" 503 UF upstream_reset_before_response_started{connection_termination} - "-" 0 95 3 - "-" "curl/8.4.0" "..." "notification-service" "10.244.0.12:8084" outbound|80||notification-service.mtlsfail-demo.svc.cluster.local ...
> --- destination ---
> ```
>
> Four details, read together, are the whole diagnosis:
>
> - **Flag `UF`** — upstream connection failure. The proxy could not establish a usable connection.
> - **Details `upstream_reset_before_response_started{connection_termination}`** — the connection was terminated before any response began, which is precisely the handshake rejection from [Part 1](./course-01-two-objects-two-ends.md).
> - **Upstream host `10.244.0.12:8084`** — an address, not a `-`. The proxy knew where to go and got that far. Contrast with `NC`, where this field is empty because no destination was ever chosen.
> - **Nothing on the destination** — the request never became a request there, so no line was written.

That combination — an upstream address **and** a `UF` **and** silence on the far side — does not occur for any other common failure.

## Why the destination is silent

It is worth being precise about this, because "the destination logged nothing" is easy to misread as "the destination is unreachable".

An access log entry is written when a **request** completes. On the inbound path, a connection must first be accepted by the 15006 listener and matched to a filter chain; with `STRICT`, that chain requires a TLS handshake. Plaintext bytes arriving where a `ClientHello` was expected fail the handshake, and the connection is closed at the transport layer — one level below anything that produces an HTTP access log line.

So the silence is not an absence of evidence. It locates the failure precisely: **below HTTP, on the receiving side.**

If you want to see the server's account of it, the proxy's own operational log (as opposed to its access log) carries connection-level messages, and raising the `connection` scope makes them verbose:

```sh
POD=$(kubectl -n mtlsfail-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config log $POD -n mtlsfail-demo --level connection:debug
# reproduce the request, then:
kubectl -n mtlsfail-demo logs $POD -c istio-proxy --tail=40 | grep -i -E 'tls|handshake|remote close'
istioctl proxy-config log $POD -n mtlsfail-demo --level connection:info
```

That is [module 010-02 Part 2's](../../section-010/module-02/course-02-envoy-log-scopes-at-runtime.md) technique applied here — and a reminder to put the level back.

## Discriminating against the neighbours

Placed next to the other `503` signatures from this course, the discrimination is sharp:

| Flag | Upstream host | Destination logged | Diagnosis |
| --- | --- | --- | --- |
| `NC` | `-` | no | the route named a cluster that does not exist |
| `UH` | `-` | no | the cluster exists with no usable endpoints |
| **`UF`** | **an address** | **no** | **connection or handshake failed — mTLS, wrong port, network policy** |
| `UC` | an address | maybe | connected, then dropped mid-request |
| `-` (403) | an address | **yes** | authorization refused it after it arrived |

Read the middle two columns first. They partition the failures into "never chose a destination", "chose one and could not connect", and "connected and something later went wrong" — without knowing anything about the configuration.

## Reading the effective mode, not one object

Part 1's checkpoint read the two objects directly, which works when there are two. On a real cluster there may be a mesh-wide `PeerAuthentication` in `istio-system`, a namespace-scoped one, and a workload-scoped one, resolving narrowest-first and per port ([module 010-02 Part 1](../../section-010/module-02/course-01-what-describe-resolves.md)).

Reading objects by hand in that situation invites getting the precedence wrong and confidently concluding the wrong mode. `istioctl x describe pod` performs the resolution for you.

> [!TIP]
> **Try it — the effective mode, not the declared one**
>
> ```sh
> POD=$(kubectl -n mtlsfail-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
> istioctl x describe pod $POD -n mtlsfail-demo | grep -i -A3 -E 'peerauthentication|mtls'
> ```
>
> Expect something like:
>
> ```text
> Effective PeerAuthentication:
>    Workload mTLS mode: STRICT
> ```
>
> One line, after merging every `PeerAuthentication` that could apply, per port. When a mismatch is suspected on a cluster you did not configure yourself, this is the command to run before reading any YAML — and if it reports a mode you did not expect, the surprise is the finding.

## The second cause of the same signature

`UF` with a silent destination has a short list of causes, and only the first is what this module is fixing:

1. **An mTLS mode mismatch** — the subject here.
2. **A caller outside the mesh** calling a `STRICT` workload. No sidecar means plaintext and no client certificate, so the destination rejects the handshake identically. The tell is that there is **no client-side access log at all** — the caller has no proxy to write one. [Part 3](./course-03-fixing-and-proving-encryption.md) covers the fix, which is different.
3. **A wrong port** — the proxy connected to a port nothing is listening on, or to a port whose protocol was misdeclared.

All three are configuration problems between two healthy workloads, and none produces anything in an application log.

> [!WARNING]
> **Pitfalls in reading the signature**
>
> - **Reading only the client's log.** The *absence* of a destination-side line is half the signature, and you cannot see an absence you did not look for.
> - **Reading "no destination log" as "destination unreachable".** It means the connection was refused below HTTP — which is a much more specific finding.
> - **Ignoring the upstream host field.** An address distinguishes `UF` from `NC` and `UH` immediately.
> - **Assuming `PeerAuthentication` at one scope is the whole story.** Mesh, namespace and workload policies merge per port. Use `istioctl x describe pod`.
> - **Leaving `connection:debug` enabled after the investigation.** It is runtime state on that proxy and costs CPU until the pod restarts.
> - **Concluding "mTLS mismatch" without checking the caller is in the mesh.** An unmeshed client produces the same server-side behaviour and needs a different fix.

> *An upstream address with a UF flag and nothing on the far side: the destination was found, reached, and refused below HTTP.*

## Reference

- [Envoy response flags](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage#config-access-log-format-response-flags) — the precise definition of `UF` and its neighbours.
- [Mutual TLS migration](https://istio.io/latest/docs/tasks/security/authentication/mtls-migration/) — the `PERMISSIVE`-to-`STRICT` transition during which this failure typically appears.
- [Peer authentication reference](https://istio.io/latest/docs/reference/config/security/peer_authentication/) — scope precedence, for reading the effective mode by hand when you must.
- [Change Envoy logging levels](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/#change-envoy-message-logging-levels) — the `connection` scope used above.
