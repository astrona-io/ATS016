# The Signature

When the server requires mutual TLS (mTLS) and the client's proxy is told to send plain text, the destination's proxy closes the connection before any request exists. This part shows the evidence that leaves behind: one response flag on the client's side and nothing on the destination's side. Then it confirms the cause against the destination's *effective* mTLS mode, not against a single object.

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
NAME                                      READY   STATUS    RESTARTS   AGE
notification-service-v1-6c9f8b7d5-x2kqp   2/2     Running   0          7m
tester-6d9f7b8c5-hj4kz                    2/2     Running   0          7m
```

The destination is `2/2 Running`, so it runs its application container and its sidecar proxy, and nothing has restarted. A `503` from a missing subset looks exactly the same. The status code cannot tell the two apart, but the access logs can.

## The pair of logs

The evidence is not one line but a **pair**: the access log of the client's proxy and the access log of the destination's proxy, read for the same request. Read the newest lines on both sides:

```sh
kubectl -n mtlsfail-demo logs deploy/tester -c istio-proxy --tail=3
echo '--- destination ---'
kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

You should see something like:

```text
[...] "POST /notify HTTP/1.1" 503 UF upstream_reset_before_response_started{connection_termination} - "-" 0 95 3 - "-" "curl/8.4.0" "..." "notification-service" "10.244.0.12:8084" outbound|80||notification-service.mtlsfail-demo.svc.cluster.local ...
--- destination ---
```

Four details, read together, are the whole diagnosis:

- **The flag `UF`**: upstream connection failure. The `tester` pod's proxy could not set up a usable connection.
- **The details `upstream_reset_before_response_started{connection_termination}`**: the connection was closed before any response began. The destination's proxy closed it.
- **The upstream host `10.244.0.12:8084`**: an address, not a `-`. The proxy knew where to go and got that far. With the flag `NC`, this field is `-`, because no destination was ever chosen.
- **Nothing on the destination**: the request never became a request there, so its proxy wrote no line.

An upstream address, a `UF` flag and silence on the destination: no other common failure gives you that combination.

## Why the destination is silent

Be precise here, because "the destination logged nothing" is easy to misread as "the destination is unreachable". The proxy writes an access log line when a **request** completes. On the way in, the destination proxy's listener on port `15006` must first accept the connection and match it to a filter chain. With `STRICT`, the matching chain requires a TLS handshake. Plain-text bytes arrive where the first TLS message was expected, so the proxy closes the connection at the transport layer. That is one level below anything that produces an HTTP access log line.

So the silence is evidence. It tells you exactly where the failure is: **below HTTP, on the receiving side.**

The proxy also writes its own operational log, separate from the access log, and you can raise the level of one logging scope while it runs. Raising the `connection` scope to `debug` makes the destination's proxy log each connection event. Raise it, send a request again, read the log, then put the level back:

```sh
POD=$(kubectl -n mtlsfail-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config log $POD -n mtlsfail-demo --level connection:debug
# reproduce the request, then:
kubectl -n mtlsfail-demo logs $POD -c istio-proxy --tail=40 | grep -i -E 'tls|handshake|remote close'
istioctl proxy-config log $POD -n mtlsfail-demo --level connection:info
```

The last command matters as much as the first. The `debug` level is runtime state on that one proxy, and it costs processing time until you set it back or the pod restarts.

## Telling it apart from its neighbours

Next to the other `503` signatures, this one stands out clearly. Read the middle two columns first:

| Flag | Upstream host | Destination logged | Diagnosis |
| --- | --- | --- | --- |
| `NC` | `-` | no | the route named a cluster that does not exist |
| `UH` | `-` | no | the cluster exists with no usable endpoints |
| **`UF`** | **an address** | **no** | **connection or handshake failed: mTLS, wrong port, network policy** |
| `UC` | an address | maybe | connected, then the upstream closed the connection during the request |
| `-` (`403`) | an address | **yes** | authorization refused the request after it arrived |

Those two columns split the failures into "never chose a destination", "chose one and could not connect", and "connected, and something went wrong later". You need to know nothing about the configuration to read them.

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
```

That one line is the result after every `PeerAuthentication` that could apply has been merged. When you suspect a mismatch on a cluster you did not configure, run this before you read any YAML. If it reports a mode you did not expect, the surprise is your finding.

## The other causes of the same signature

`UF` with a silent destination has a short list of causes, and only the first one is the subject of this module. The first is an mTLS mode mismatch: the server is `STRICT` and the client's `DestinationRule` sends plain text. The second is a caller outside the mesh calling a `STRICT` workload. With no sidecar proxy, the caller sends plain text and has no client certificate, so the destination closes the connection the same way. The tell is that there is **no client-side access log at all**, because the caller has no proxy to write one, and the fix is to bring the caller into the mesh. The third is a wrong port: the proxy connected to a port nothing listens on, or to a port with the wrong declared protocol.

All three are configuration problems between two healthy workloads, and none of them shows up in an application log.

You can now read the signature of an mTLS mismatch: a `UF` flag with an upstream address on the client's proxy, and silence on the destination's proxy. You know why the destination is silent, and you can read the destination's effective mTLS mode in one command. What is still open is which of the two objects to change, and how to prove that the fixed traffic is encrypted.

## Common pitfalls

> [!WARNING]
> - **Reading only the client's log.** The *absence* of a destination line is half the signature, and you cannot see an absence you did not look for.
> - **Reading "no destination log" as "destination unreachable".** It means the connection was closed below HTTP, which is a much more specific finding.
> - **Ignoring the upstream host field.** An address separates `UF` from `NC` and `UH` at once.
> - **Assuming one `PeerAuthentication` is the whole story.** Mesh, namespace and workload policies merge per port. Use `istioctl x describe pod`.
> - **Leaving `connection:debug` switched on.** It stays on that proxy and costs processing time until the pod restarts.
> - **Concluding "mTLS mismatch" without checking that the caller is in the mesh.** A caller without a sidecar proxy gives the same server-side behaviour and needs a different fix.
