# The Signature

When the server requires mutual TLS (mTLS) and the client's proxy is told to send plain text, the destination's proxy closes the connection before any request exists. This part shows the evidence that leaves behind: one response flag on the client's side and one connection-level line on the destination's side. Then it confirms the cause against the destination's *effective* mTLS mode, not against a single object.

## The symptom looks ordinary

At first sight this failure looks like any other `503`. The pods are healthy, nothing restarted, and the status code names nothing. Send one request from the `tester` pod to the `notification-service` Service, then list the pods:

<!-- astrona:playground:renew -->

```sh
kubectl -n mtlsfail-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n mtlsfail-demo get pods
```

You should see something like:

```text
503
NAME                                       READY   STATUS    RESTARTS   AGE
notification-service-v1-54dd46d4b6-pwjbh   2/2     Running   0          11s
tester-69699fd775-xrfn8                    2/2     Running   0          11s
```

The destination is `2/2 Running`, so it runs its application container and its sidecar proxy, and nothing has restarted. A `503` from a missing subset looks exactly the same. The status code cannot tell the two apart, but the access logs can.

## The pair of logs

The evidence is not one line but a **pair**: the access log of the client's proxy and the access log of the destination's proxy, read for the same request. Read the newest lines on both sides:

```sh
kubectl -n mtlsfail-demo logs deploy/tester -c istio-proxy --tail=3
echo '--- destination ---'
kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

You should see something like this (shortened to the access log lines; the other lines are start-up messages of the proxy):

```text
[2026-10-09T22:26:48.133Z] "POST /notify HTTP/1.1" 503 UC upstream_reset_before_response_started{connection_termination} - "-" 0 95 1 - "-" "curl/8.22.0" "56fd0f76-70e7-9135-a60e-66799df83b62" "notification-service" "10.244.0.8:8084" outbound|80||notification-service.mtlsfail-demo.svc.cluster.local 10.244.0.9:45690 10.96.172.178:80 10.244.0.9:36914 - default
--- destination ---
[2026-10-09T22:26:48.133Z] "- - -" 0 NR filter_chain_not_found - "-" 0 0 0 - "-" "-" "-" "-" "-" - - 10.244.0.8:8084 10.244.0.9:45690 - -
```

Five details, read together, are the whole diagnosis:

- **The flag `UC` on the client's line**: upstream connection termination. The connection to the destination was set up, and then the other side closed it.
- **The details `upstream_reset_before_response_started{connection_termination}`**: the connection was closed before any response began.
- **The upstream host `10.244.0.8:8084`**: an address, not a `-`. The client's proxy chose a destination pod and connected to it. With the flag `NC` or `UH`, this field is `-`, because no destination was ever chosen.
- **The destination's line `"- - -" 0 NR filter_chain_not_found`**: no method, no path and status `0`. This is a connection-level line, not an HTTP request. The flag `NR` with the details `filter_chain_not_found` means the destination's inbound listener had no filter chain for this connection.
- **The same connection on both lines**: the client's local address `10.244.0.9:45690` is the remote address on the destination's line. Both lines describe one TCP connection.

An upstream address with `UC` on the client, and `filter_chain_not_found` on the destination: no other common failure gives you that combination.

## Why the destination writes no request line

Be precise here, because "the destination logged no request" is easy to misread as "the destination is unreachable". The proxy writes an HTTP access log line when a **request** completes. On the way in, the destination proxy's listener on port `15006` must first accept the connection and match it to a filter chain. With `STRICT`, every filter chain requires TLS. A plain-text connection matches none, so the proxy closes it at the transport layer and logs only the connection, with `filter_chain_not_found`. That is one level below anything that produces an HTTP request line.

So the missing request line is evidence too. It tells you exactly where the failure is: **below HTTP, on the receiving side.**

## Telling it apart from its neighbours

Next to the other `503` signatures, this one stands out clearly. Read the middle two columns first:

| Client flag | Upstream host | Destination logged | Diagnosis |
| --- | --- | --- | --- |
| `NC` | `-` | nothing | the route named a cluster that does not exist |
| `UH` | `-` | nothing | the cluster exists with no healthy endpoints |
| `UF` | an address | nothing | the connection could not be set up: nothing listens on the port, or the network drops it |
| **`UC`** | **an address** | **`"- - -" 0 NR filter_chain_not_found`** | **connected, and the destination closed it: an mTLS mismatch** |
| `-` (`403`) | an address | a `403` request line | authorization refused the request after it arrived |

Those two columns split the failures into "never chose a destination", "chose one and could not connect", and "connected, and the other side refused or closed it". You need to know nothing about the configuration to read them.

## Reading the effective mode, not one object

Reading the two objects directly works when there are only two. A real cluster may have a mesh-wide `PeerAuthentication` in `istio-system`, one for the namespace and one for the workload. They resolve narrowest first, and per port: a policy for a workload beats one for its namespace, which beats the mesh-wide one.

Working that out by hand invites mistakes. `istioctl x describe pod` does it for you: it prints the Services, routing rules and policies that apply to one pod, including the effective mTLS mode after all `PeerAuthentication` objects are merged. Ask it for the destination pod:

```sh
POD=$(kubectl -n mtlsfail-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
istioctl x describe pod $POD -n mtlsfail-demo | grep -i -A3 -E 'peerauthentication|mtls'
```

You should see something like:

```text
Effective PeerAuthentication:
   Workload mTLS mode: STRICT
Applied PeerAuthentication:
   default.mtlsfail-demo
```

The first line is the result after every `PeerAuthentication` that could apply has been merged. The second names the objects that took part, as `<name>.<namespace>`. When you suspect a mismatch on a cluster you did not configure, run this before you read any YAML. If it reports a mode you did not expect, the surprise is your finding.

## The other cause of the same destination line

The destination line `filter_chain_not_found` has a second common cause besides the subject of this module. The first cause is an mTLS mode mismatch: the server is `STRICT` and the client's `DestinationRule` sends plain text. The second is a caller outside the mesh calling a `STRICT` workload. With no sidecar proxy, the caller sends plain text and has no client certificate, so the destination closes the connection the same way and writes the same line. The tell is that there is **no client-side access log at all**, because the caller has no proxy to write one, and the fix is to bring the caller into the mesh.

Both causes are configuration problems between two healthy workloads, and neither shows up in an application log.

You can now read the signature of an mTLS mismatch: `UC` with an upstream address on the client's proxy, and `NR filter_chain_not_found` on the destination's proxy. You know why the destination writes no request line, and you can read the destination's effective mTLS mode in one command. What is still open is which of the two objects to change, and how to prove that the fixed traffic is encrypted.

## Common pitfalls

> [!WARNING]
> - **Reading only the client's log.** The destination's `filter_chain_not_found` line is half the signature, and the missing request line is the other half.
> - **Reading "no request line on the destination" as "destination unreachable".** It means the connection was closed below HTTP, which is a much more specific finding.
> - **Ignoring the upstream host field.** An address separates `UC` and `UF` from `NC` and `UH` at once.
> - **Mixing up `UC` and `UF`.** `UF` means the connection could not be set up at all; `UC` means it was set up and then closed by the other side.
> - **Assuming one `PeerAuthentication` is the whole story.** Mesh, namespace and workload policies merge per port. Use `istioctl x describe pod`.
> - **Concluding "mTLS mismatch" without checking that the caller is in the mesh.** A caller without a sidecar proxy gives the same server-side line and needs a different fix.
