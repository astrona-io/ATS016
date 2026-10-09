# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about a `503` that comes from two healthy ships failing to agree on the secret handshake: an mTLS mismatch.

**From [Two Objects, Two Ends Of One Connection](./course-01-two-objects-two-ends.md):**

- `PeerAuthentication` (`spec.mtls.mode`) sets what the server accepts; `DestinationRule` (`spec.trafficPolicy.tls.mode`) sets what the client sends. Nothing compares the two.
- `STRICT` with `DISABLE` fails, `DISABLE` with `ISTIO_MUTUAL` fails, and `PERMISSIVE` accepts anything.
- No `DestinationRule` at all is the safe default: traffic between sidecars is mTLS automatically.
- The server refuses a plain-text connection at the transport layer, before any HTTP request exists.

**From [The Signature](./course-02-the-signature.md):**

- The signature is the flag `UF`, an upstream address, and **nothing** in the destination's access log.
- The destination is silent because the handshake fails below HTTP, so there is no request to log.
- `istioctl x describe pod` shows the effective mTLS mode after merging every `PeerAuthentication`.
- A caller outside the mesh produces the same server-side behaviour, but has no client-side log at all.

**From [Fixing It, And Proving Encryption](./course-03-fixing-and-proving-encryption.md):**

- Keep the server `STRICT`; fix the client by removing the `tls:` override (or setting `ISTIO_MUTUAL`).
- Prove the fix three ways: a `200`, `connection_security_policy="mutual_tls"` on the destination, and lines in the destination's access log.
- A caller outside the mesh is fixed by bringing it into the mesh, or by a narrow `portLevelMtls` exemption, never by relaxing the whole server.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [A 503 Where The Destination Log Is Empty](./labs/lab-01/README.md) | Fixing It, And Proving Encryption | find the mismatch from both logs, fix the client while the server stays `STRICT`, and prove `mutual_tls` |

If you skipped it, go back to it now. The mission is short.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. Which object sets what the server accepts, and which sets what the client sends?</summary>

`PeerAuthentication` sets the server side with `spec.mtls.mode`. `DestinationRule` sets the client side with `spec.trafficPolicy.tls.mode`.
</details>

<details>
<summary>2. Why can a <code>DestinationRule</code> with <code>tls: DISABLE</code> work for a year and then suddenly fail?</summary>

While the server is `PERMISSIVE`, it accepts plain text, so the client works. The day someone tightens the namespace to `STRICT`, the plain-text client is refused.
</details>

<details>
<summary>3. The client logs <code>503 UF</code> with an upstream address, and the destination's access log is empty. What happened?</summary>

The client's proxy reached the destination, but the connection was reset during the handshake, below HTTP. No request ever existed on the destination, so its proxy wrote no line. This points at an mTLS mismatch, a caller outside the mesh, or a wrong port.
</details>

<details>
<summary>4. Why use <code>istioctl x describe pod</code> instead of reading the <code>PeerAuthentication</code> directly?</summary>

Mesh-wide, namespace and workload policies merge, narrowest first and per port. `describe` shows the effective mode after that merge; one object on its own may not be the one that applies.
</details>

<details>
<summary>5. Why is removing the <code>tls:</code> block better than setting <code>ISTIO_MUTUAL</code>?</summary>

Both work, but the default is already mesh mTLS. Removing the override leaves nothing that can drift, get copied, or disagree with a later server change.
</details>

<details>
<summary>6. After the fix you get a <code>200</code>. Why is that not enough?</summary>

A `200` would also appear if the server had been relaxed to `PERMISSIVE` with the client still sending plain text. Check `connection_security_policy="mutual_tls"` on the destination proxy to prove encryption.
</details>

<details>
<summary>7. The same signature appears, but the caller pod shows <code>1/1</code> and is missing from <code>istioctl proxy-status</code>. What is the fix?</summary>

The caller has no sidecar, so it is outside the mesh. Bring it into the mesh. Do not relax the server; if something truly cannot join the mesh, exempt only one port with `portLevelMtls`.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-050-02
```

If `astrona list` also showed the mission, remove it the same way:

```sh
astrona destroy ats-016-lab-050-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with `astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-02/playground`. It always starts clean, so nothing you broke carries over.

> *Two objects, two ends, one handshake: fix the end that is wrong, and prove the traffic is encrypted, not just working.*
