# Fixing It, And Proving Encryption

Astronaut, in an mTLS mismatch both ends are wrong relative to each other. So "which object is wrong" is a judgement, not a lookup. The wrong judgement gives you working traffic with no encryption, which is worse than the failure it replaced. This part makes the choice explicit, applies the fix that removes configuration instead of adding it, and then proves the result three ways.

## Which end to change

You have two objects in conflict: the server's `PeerAuthentication` (the airlock rule) set to `STRICT`, and the client's `DestinationRule` set to `tls.mode: DISABLE` (approach the airlock without the handshake). Only one of them should change.

### Keep the server STRICT

**`STRICT` on the server is almost always the setting you want.** It is what a mesh is for: no handshake, no docking. Relaxing it to `PERMISSIVE` to make an error go away costs more than it looks:

- It weakens the rule for **every** client of that workload, not just the broken one. One misconfigured caller becomes a reason to accept plain text from anywhere.
- It turns a loud failure into a silent one. Traffic starts working, unencrypted, and nothing reports it. A plain-text client against a `PERMISSIVE` server can go unnoticed for a year.

### Fix the client

**`tls: DISABLE` on the client is almost always a mistake**, and usually an inherited one: a `tls:` block copied along with a `DestinationRule` that was written for load balancing or connection pooling.

So the fix goes on the client. Two forms are correct, and they are not equal:

| Fix | Effect | Verdict |
| --- | --- | --- |
| set `tls.mode: ISTIO_MUTUAL` | explicitly asks for mesh mTLS | correct, and one more setting to keep right |
| **remove the `tls:` block** | Istio's default applies: mesh mTLS | **better** |

Removing it is better, for a reason that applies everywhere: the default is already correct. Pinning it in configuration adds something that can drift, get copied, or disagree with a future server change. Delete the override, and keep the rest of the `DestinationRule`, which was written for something else.

<!-- astrona:playground:renew -->

### Remove the override

Remove exactly one path from the `DestinationRule` with a JSON Patch, then send a request again:

```sh
kubectl -n mtlsfail-demo patch destinationrule notification --type json \
  -p '[{"op":"remove","path":"/spec/trafficPolicy/tls"}]'
kubectl -n mtlsfail-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

You should see something like:

```text
destinationrule.networking.istio.io/notification patched
200
```

A JSON Patch `remove` on one path, so the `DestinationRule` still exists and still governs everything else it was written for. Istio's default takes over and attaches Istio's certificates to the tester's outbound cluster for this host. `istiod` (mission control) radios the new cluster settings to the tester's proxy over the running connection (a CDS push, the Cluster Discovery Service), so the handshake succeeds within a second, with no restart.

## Working is not the same as encrypted

A `200` proves the handshake succeeded. But a `200` would *also* appear if someone had "fixed" this by setting the server to `PERMISSIVE` and left the client sending plain text. Those are different outcomes with the same status code, and on a mesh whose point is encryption you must tell them apart.

Istio's metrics hold the answer. Every request the destination proxy handles adds one to the counter `istio_requests_total`, with the label `connection_security_policy`:

| Value | Means |
| --- | --- |
| `mutual_tls` | the connection was mTLS |
| `none` | plain text |
| `unknown` | reported by a proxy that cannot know, usually on the client side |

The label is meaningful on the **destination**, because the receiving proxy is the one that knows how the connection was secured.

### Ask the destination how the connection was secured

Read the destination proxy's own statistics and count the values of the label:

```sh
kubectl -n mtlsfail-demo exec deploy/notification-service-v1 -c istio-proxy -- \
  pilot-agent request GET stats/prometheus \
  | grep istio_requests_total | grep -o 'connection_security_policy="[^"]*"' | sort | uniq -c
```

You should see something like:

```text
   4 connection_security_policy="mutual_tls"
```

`mutual_tls` on every counted request. `pilot-agent request GET` reads the sidecar's administration interface from inside the container. That is how you read a proxy's statistics when there is no Prometheus in the cluster.

If this had printed `none`, the traffic would be working and unencrypted, and the fix would have gone on the wrong end.

## The log that was empty

The most direct confirmation is the destination's flight log (its access log). During the failure it logged nothing, because the connection was reset before any request existed. Now it should log every request.

### Read the destination's log again

Read the newest lines of the destination proxy's access log:

```sh
kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

You should see something like:

```text
[...] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 14 1 1 "-" "curl/8.4.0" "..." "notification-service" "10.244.0.12:8084" inbound|8084|| ...
```

Requests are arriving and being served, logged against the `inbound|8084||` cluster. The absence of exactly these lines was the signature of the failure. Their presence is the cleanest proof that the handshake now completes, and that requests become requests on the far side.

Three confirmations, each answering a different question. The `200` says it works. `connection_security_policy` says it is encrypted. The destination's log says the request arrived. A fix that cannot show all three is not finished.

## The variant with no DestinationRule at all

The same `UF` signature appears in a second situation, with a completely different fix: a workload **outside the mesh** calling a `STRICT` workload. With no sidecar, the caller sends plain text and cannot show a certificate, so the destination rejects the handshake the same way.

The tells:

- There is **no client-side access log** to read. The caller has no proxy to write one.
- The calling pod shows `1/1`, not `2/2`: no communications officer on board.
- The caller does not appear in `istioctl proxy-status`, mission control's roll call.

The fix is to bring the caller into the mesh, **not** to relax the server. Relaxing the server to `PERMISSIVE` would make it work, and would leave the caller outside every policy the mesh enforces for good.

There is a fair middle ground: `portLevelMtls` on the `PeerAuthentication` can exempt one port from `STRICT` while the rest of the workload stays strict. That is the right tool when something truly cannot join the mesh, such as an old metrics scraper or an outside health check, because it limits the exception to one port.

## The method

Work these steps in order:

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

Step 2 before step 5 is the order that matters. Both situations look the same on the server; only the caller's own state separates them. Fix the wrong one and you get plain-text traffic that everybody believes is encrypted.

## Common pitfalls

> [!WARNING]
> - **Relaxing the server to `PERMISSIVE` to make it work.** It removes the failure and the guarantee together, for every client of that workload.
> - **Trusting a `200` as proof of encryption.** Check `connection_security_policy` on the destination; `PERMISSIVE` serves plain text with a healthy status code.
> - **Adding `ISTIO_MUTUAL` when removing the block would do.** The default is already correct; an explicit setting is one more thing to drift.
> - **Deleting the whole `DestinationRule`.** It was probably written for load balancing or connection pooling. Remove the `tls:` path only.
> - **Fixing the server when the caller has no sidecar.** Same symptom, different cause: bring the caller into the mesh, or scope an exemption with `portLevelMtls`.
> - **Stopping at one confirmation.** Working, encrypted and arriving are three separate claims.

> *Fix the end that is wrong, then prove the traffic is encrypted, because "it works now" is exactly what the wrong fix also produces.*

## Your mission: A 503 Where The Destination Log Is Empty

You can now read the `UF`-and-silence signature, fix the client end of an mTLS mismatch, and prove the traffic is encrypted. The mission gives you a namespace where every request returns `503`, the server must stay `STRICT`, and you must prove `mutual_tls` on the destination.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-050-02
```

Then start the mission:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-02/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-050/module-02/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-016-lab-050-02
astrona start ats-016-playground-050-02
```
