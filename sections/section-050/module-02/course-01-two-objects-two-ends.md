# Part 1 — Two Objects, Two Ends Of One Connection

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — The Signature](./course-02-the-signature.md).

Everything about this failure follows from one structural fact: the two halves of an mTLS connection are configured by two unrelated objects, in two different API groups, with no reference between them. This part is that split — what each side controls, what every mode means, and what the settings become in the proxies.

## The split

| | Object | API group | Field | Values |
| --- | --- | --- | --- | --- |
| **Server** — what will be accepted | `PeerAuthentication` | `security.istio.io` | `spec.mtls.mode` | `STRICT`, `PERMISSIVE`, `DISABLE`, `UNSET` |
| **Client** — what will be sent | `DestinationRule` | `networking.istio.io` | `spec.trafficPolicy.tls.mode` | `ISTIO_MUTUAL`, `SIMPLE`, `MUTUAL`, `DISABLE` |

Nothing validates the pair. The `DestinationRule` names a host, not a policy; the `PeerAuthentication` selects pods, not callers. Each is checked for internal consistency at admission and neither is checked against the other — the cross-object class from [module 010-01 Part 1](../../section-010/module-01/course-01-admission-and-the-analysis-gap.md).

## Server modes: what will be accepted

- **`STRICT`** — only mTLS connections are accepted. Plaintext is refused at the transport layer.
- **`PERMISSIVE`** — either mTLS or plaintext is accepted, decided per connection.
- **`DISABLE`** — mTLS is not used for this workload; plaintext is expected.
- **`UNSET`** — inherit from a wider scope, or the mesh default (`PERMISSIVE` in a standard install).

`PERMISSIVE` deserves more than a line, because it explains why these mismatches survive so long. It exists to make mesh adoption incremental: a workload can be onboarded while half its callers are still outside the mesh, and nothing breaks. The cost is that a client sending plaintext against a `PERMISSIVE` server works perfectly — so a `DestinationRule` with `tls: DISABLE` can sit in a repository for a year, doing exactly what it says, until somebody tightens the namespace to `STRICT` and a service that "nobody touched" starts failing.

`PeerAuthentication` also supports `portLevelMtls`, which overrides the mode for specific ports. That is how a health-check or metrics port gets exempted from `STRICT` without weakening the workload.

## Client modes: what will be sent

- **`ISTIO_MUTUAL`** — mTLS using the certificates Istio manages. The correct choice inside the mesh; no certificate configuration is needed because `istiod` already issued both ends' identities.
- **`SIMPLE`** — ordinary one-way TLS: verify the server, present no client certificate. For external services.
- **`MUTUAL`** — mTLS with certificates **you** supply, referenced from the `DestinationRule`. For external services that require client certificates.
- **`DISABLE`** — send plaintext.

`MUTUAL` and `ISTIO_MUTUAL` are one word apart and mean different things. `MUTUAL` without a certificate reference is a configuration error; `ISTIO_MUTUAL` is the one that "just works" between meshed workloads.

## The combinations

| Server (`PeerAuthentication`) | Client (`DestinationRule`) | Result |
| --- | --- | --- |
| `STRICT` | `ISTIO_MUTUAL`, or **no `DestinationRule` at all** | works |
| `STRICT` | `DISABLE` | **fails** — plaintext arriving at a TLS-only listener |
| `DISABLE` | `ISTIO_MUTUAL` | **fails** — TLS arriving at a plaintext listener |
| `PERMISSIVE` | anything | works |

The first row carries the most useful fact in this module: **no `DestinationRule` is the safe default.** Left alone, sidecar-to-sidecar traffic uses mTLS automatically, because the injected proxies already have identities and Istio configures them to use them.

It follows that almost every mismatch in practice comes from a `DestinationRule` written for some *other* reason — a load balancer setting, a connection pool, an outlier detection policy — that happens to carry a `tls:` block someone copied along with it. The TLS setting was never the point of the object, which is exactly why nobody reviews it.

> [!TIP]
> **Try it — what each object asks for**
>
> ```sh
> kubectl -n mtlsfail-demo get peerauthentication -o yaml | grep -A3 'mtls:'
> kubectl -n mtlsfail-demo get destinationrule -o yaml | grep -A3 'tls:'
> ```
>
> Expect something like:
>
> ```text
>     mtls:
>       mode: STRICT
>       tls:
>         mode: DISABLE
> ```
>
> Four lines, and the contradiction is visible only because you are reading both at once. The server requires mTLS; the client is told to send plaintext. Each object is valid, each is defensible on its own terms, and neither mentions the other — which is why this configuration survived being written and reviewed.

## What the settings become

Both objects end up as Envoy configuration, and knowing which part makes the failure mode predictable.

**On the server**, `PeerAuthentication` configures the **transport socket** on the inbound listener's filter chains ([module 040-01 Part 4](../../section-040/module-01/course-04-inbound-secrets-and-method.md)):

```text
   STRICT       inbound 15006 has ONE filter chain, requiring TLS with a client certificate
   PERMISSIVE   inbound 15006 has TWO chains, matched on whether the connection is TLS:
                    tls      → mTLS chain
                    raw_buffer → plaintext chain
   DISABLE      inbound 15006 has one plaintext chain
```

`PERMISSIVE` being literally an extra filter chain is worth seeing once — it is the same chain-matching mechanism that handles protocol sniffing, applied to transport security.

**On the client**, `DestinationRule` `tls.mode` configures the transport socket on the **outbound cluster** for that host. `ISTIO_MUTUAL` attaches Istio's certificates; `DISABLE` attaches nothing.

You can read both directly:

```sh
istioctl proxy-config cluster deploy/tester -n mtlsfail-demo \
  --fqdn notification-service.mtlsfail-demo.svc.cluster.local -o json | grep -i -A3 transport_socket
istioctl proxy-config listener deploy/notification-service-v1 -n mtlsfail-demo \
  --port 15006 -o json | grep -c 'filter_chains'
```

## Why the failure is a handshake failure

Put the two together and the mechanism is unavoidable:

```text
   client cluster: plaintext            server listener: requires TLS
        │                                      │
        ├── TCP connect ──────────────────────▶│  accepted
        │                                      │
        ├── sends HTTP bytes ─────────────────▶│  expects a TLS ClientHello,
        │                                      │  sees something else
        │                                      │
        │◀──────── connection reset ───────────┤  closed before any request exists
        │
        ▼
   client proxy: "upstream connection failure"  → 503, flag UF
```

The TCP connection succeeds. What fails is the **first thing that happens on it**. The server proxy closes the connection before an HTTP request has been parsed — before, in fact, there is any HTTP at all — which means there is nothing for it to write an access log line about.

That is the whole explanation for the signature in [Part 2](./course-02-the-signature.md): a failure on the client, and silence on the server, not because the server is unreachable but because the request never became a request.

> [!WARNING]
> **Pitfalls in the model**
>
> - **Adding a `DestinationRule` where none is needed.** Sidecar-to-sidecar traffic is already mTLS by default. Every `tls:` block you write is an opportunity to disagree with the server.
> - **Using `MUTUAL` instead of `ISTIO_MUTUAL`.** `MUTUAL` means "mTLS with certificates I supply". Inside the mesh you want Istio's, which is `ISTIO_MUTUAL`.
> - **Assuming `PERMISSIVE` is a safe permanent state.** It works, and it hides which callers are still sending plaintext. It is a migration mode, not a destination.
> - **Believing a `DestinationRule` is about security because it has a `tls` field.** It is a client-side traffic policy object; the security posture is set by `PeerAuthentication` on the server.
> - **Expecting the API server to catch the mismatch.** The two objects are never compared at admission.

> *The server declares what it will accept and the client declares what it will send — and nothing anywhere checks that those two agree.*

## Reference

- [Peer authentication reference](https://istio.io/latest/docs/reference/config/security/peer_authentication/) — the modes, scope precedence and `portLevelMtls`.
- [Destination rule — ClientTLSSettings](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ClientTLSSettings) — `ISTIO_MUTUAL`, `SIMPLE`, `MUTUAL` and `DISABLE`, with the fields each requires.
- [Mutual TLS migration](https://istio.io/latest/docs/tasks/security/authentication/mtls-migration/) — the `PERMISSIVE`-to-`STRICT` path this module's failure usually appears on.
- [Istio security concepts](https://istio.io/latest/docs/concepts/security/#mutual-tls-authentication) — the handshake and identity model behind the transport sockets above.
