# Fixing It, And Proving Encryption

In an mTLS mismatch, each end is only wrong compared with the other. So "which object is wrong" is a decision, not a lookup. The wrong decision gives you working traffic with no encryption, which is worse than the failure it replaced. This part makes the decision explicit, applies the fix that removes configuration instead of adding it, and then proves the result in three ways.

## Which end to change

You have two objects in conflict: the server's `PeerAuthentication` set to `STRICT`, and the client's `DestinationRule` set to `tls.mode: DISABLE`. Only one of them should change, and the reasons are different for each side.

### Keep the server STRICT

**`STRICT` on the server is almost always the setting you want.** It is what a mesh is for: every connection to the workload uses mTLS. Relaxing it to `PERMISSIVE` to make an error go away costs more than it looks. It weakens the rule for **every** client of that workload, not only the broken one, so one misconfigured caller becomes a reason to accept plain text from anywhere. It also turns a loud failure into a silent one: traffic starts working, unencrypted, and nothing reports it.

### Fix the client

**`tls.mode: DISABLE` on the client is almost always a mistake**, and usually an inherited one: a `tls:` block copied along with a `DestinationRule` that was written for load balancing or connection pooling. So the fix goes on the client. Two forms are correct, and they are not equal:

| Fix | Effect | Verdict |
| --- | --- | --- |
| set `tls.mode: ISTIO_MUTUAL` | explicitly asks for mTLS with Istio's certificates | correct, and one more setting to keep right |
| **remove the `tls:` block** | Istio's default applies: auto mTLS | **better** |

Removing it is better for a reason that applies everywhere: the default is already correct. Setting it in configuration adds something that can drift, be copied, or disagree with a future server change. Delete the override, and keep the rest of the `DestinationRule`, which was written for something else.

A JSON Patch `remove` deletes exactly one path from an object. Try to remove only the `tls` block from the `DestinationRule`:

<!-- astrona:playground:renew -->

```sh
kubectl -n mtlsfail-demo patch destinationrule notification --type json \
  -p '[{"op":"remove","path":"/spec/trafficPolicy/tls"}]'
```

You should see something like:

```text
Error from server: admission webhook "validation.istio.io" denied the request: configuration is invalid: traffic policy must have at least one field
```

`istiod`'s validating webhook refused the patch. In this playground, `tls` is the only field in `trafficPolicy`, and removing it would leave an empty `trafficPolicy`, which Istio does not accept. The object is unchanged, so the failure is still there. When `trafficPolicy` holds other settings, such as a connection pool, removing `/spec/trafficPolicy/tls` works and keeps them. Here, remove the whole `trafficPolicy`, then send a request again:

```sh
kubectl -n mtlsfail-demo patch destinationrule notification --type json \
  -p '[{"op":"remove","path":"/spec/trafficPolicy"}]'
kubectl -n mtlsfail-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

`kubectl` reports that the `DestinationRule` was patched, and the request now returns `200`. The `DestinationRule` still exists and still governs everything else it was written for. Istio's default takes over: `istiod` attaches Istio's certificates to the `tester` proxy's outbound cluster for this host. It sends the new cluster configuration to the proxy over its running connection, a CDS (Cluster Discovery Service) push, so the handshake succeeds within a second and nothing restarts.

## Working is not the same as encrypted

A `200` proves the request succeeded. But a `200` would *also* appear if someone had "fixed" this by setting the server to `PERMISSIVE` and left the client sending plain text. Those are different outcomes with the same status code, and on a mesh whose purpose is encryption you must tell them apart.

Istio's metrics hold the answer. Every request the destination's proxy handles adds one to the counter `istio_requests_total`, with the label `connection_security_policy`:

| Value | Means |
| --- | --- |
| `mutual_tls` | the connection used mTLS |
| `none` | plain text |
| `unknown` | reported by a proxy that cannot know, usually on the client's side |

The label is meaningful on the **destination's** proxy, because the receiving proxy is the one that knows how the connection was secured. Read the destination proxy's own statistics and count the values of the label:

```sh
kubectl -n mtlsfail-demo exec deploy/notification-service-v1 -c istio-proxy -- \
  pilot-agent request GET stats/prometheus \
  | grep istio_requests_total | grep -o 'connection_security_policy="[^"]*"' | sort | uniq -c
```

Each output line is a count followed by one value of the label, for example `connection_security_policy="mutual_tls"`. After the fix, every counted series reports `mutual_tls`. The first line of the output may be an `INFO GOMEMLIMIT` message from `pilot-agent` itself; it is not part of the statistics. `pilot-agent request GET` reads the sidecar proxy's administration interface from inside the container, which is how you read a proxy's statistics when there is no Prometheus in the cluster. If this had printed `none`, the traffic would be working and unencrypted, and the fix would have gone on the wrong end.

## The destination logs requests again

The most direct confirmation is the destination proxy's access log. During the failure it wrote only a connection-level line with `filter_chain_not_found`, because the connection was closed before any request existed. Now it should log every request:

```sh
kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

The newest line is now an HTTP request line: `"POST /notify HTTP/1.1" 200 - via_upstream`, logged against the `inbound|8084||` cluster. The absence of exactly these lines was half the signature of the failure, and their presence is the cleanest proof that the handshake now completes.

So there are three confirmations, and each answers a different question. The `200` says it works. `connection_security_policy` says it is encrypted. The destination's log says the request arrived. A fix that cannot show all three is not finished.

## The variant with a caller outside the mesh

The same `filter_chain_not_found` line on the destination appears in a second situation, with a completely different fix: a workload **outside the mesh** calling a `STRICT` workload. With no sidecar proxy, the caller sends plain text and cannot present a certificate, so the destination closes the connection the same way.

You can tell this variant apart in three ways. There is no client-side access log to read, because the caller has no proxy to write one. The calling pod shows `1/1` instead of `2/2`, because it has no `istio-proxy` container. And the caller does not appear in `istioctl proxy-status`, which lists every proxy connected to `istiod`.

The fix is to bring the caller into the mesh, **not** to relax the server. Relaxing the server to `PERMISSIVE` would make it work, and would leave the caller outside every policy the mesh enforces. There is a fair middle ground: `portLevelMtls` on the `PeerAuthentication` can exempt one port from `STRICT` while the rest of the workload stays strict. That is the right tool when something truly cannot join the mesh, such as an old metrics scraper or an outside health check, because it limits the exception to one port.

## The method

Work these steps in order:

```text
   1. UC + upstream address on the client, and
      NR filter_chain_not_found on the destination?    -> this class of failure
   2. Is the caller in the mesh?  (2/2, proxy-status)
          no  -> bring the caller into the mesh. Do not touch the server.
          yes -> continue
   3. istioctl x describe pod <destination pod>          -> effective server mode
   4. get destinationrule -o yaml | grep -A3 'tls:'      -> what the client sends
   5. Fix the CLIENT: remove the tls block (or ISTIO_MUTUAL)
   6. Prove three ways: 200, connection_security_policy, destination log
```

Step 2 before step 5 is the order that matters. Both situations look the same on the server, and only the caller's own state separates them. Fix the wrong one, and you get plain-text traffic that everybody believes is encrypted.

You can now fix an mTLS mismatch on the right end: keep the server `STRICT` and remove the client's `tls` override. You can also prove the result three ways, and tell a misconfigured client from a caller that is not in the mesh. Together with the access log habits of reading both proxies, that covers the most common causes of a `503` that no application log explains.

## Common pitfalls

> [!WARNING]
> - **Relaxing the server to `PERMISSIVE` to make it work.** It removes the failure and the guarantee together, for every client of that workload.
> - **Trusting a `200` as proof of encryption.** Check `connection_security_policy` on the destination's proxy; `PERMISSIVE` serves plain text with a healthy status code.
> - **Adding `ISTIO_MUTUAL` when removing the block would do.** The default is already correct, and an explicit setting is one more thing to drift.
> - **Deleting the whole `DestinationRule`.** It was probably written for load balancing or connection pooling. Remove the `tls` path only, or `trafficPolicy` when `tls` is its only field.
> - **Fixing the server when the caller has no sidecar proxy.** Same symptom, different cause: bring the caller into the mesh, or limit an exemption with `portLevelMtls`.
> - **Stopping at one confirmation.** Working, encrypted and arriving are three separate claims.

## Your mission: A 503 Where The Destination Log Is Empty

You can now read the signature of an mTLS mismatch, fix the client's end, and prove the traffic is encrypted. The graded lab gives you a namespace where every request returns `503` and the server must stay `STRICT`, and asks you to fix the mismatch and prove `mutual_tls` on the destination's proxy.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-050-02
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-02/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-050/module-02/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-050-02
astrona start ats-016-playground-050-02
```
