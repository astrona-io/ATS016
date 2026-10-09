# Flags, And Which Proxy Wrote The Line

The **response flag** is a short code that Envoy writes into the access log when the proxy itself ended or changed a request. It is only two or three characters long, yet it often tells you more than the rest of the line. This part turns the list of flags into a model you can reason with. Then it adds a second question that doubles the value of every flag: which proxy wrote the line.

## The flags

Each flag names one way a request can end. The last column says where to look next, so the flag sends you straight to the right object.

| Flag | Name | What it means | Where to look next |
| --- | --- | --- | --- |
| `-` | *(none)* | No proxy-level error. If the status is an error, the **application** produced it | application logs |
| `NR` | no route | No route matched the request (status `404`) | `Host` header, port protocol, `VirtualService` match rules and binding |
| `NC` | no cluster | The route named a cluster that does not exist | `DestinationRule` subsets, host names |
| `UH` | no healthy upstream | The cluster exists and has no usable endpoints (status `503`) | Service selector, readiness, subset labels, ejected endpoints |
| `UF` | upstream connection failure | The proxy could not set up a connection (status `503`) | mTLS mismatch, wrong port, network policy |
| `UO` | upstream overflow | A circuit breaker rejected the request (status `503`) | `DestinationRule` `connectionPool` limits |
| `UT` | upstream request timeout | The route timeout fired (status `504`) | `VirtualService` `timeout`, a slow upstream |
| `UC` | upstream connection termination | The upstream closed the connection during the request (status `503`) | application crash, protocol mismatch |
| `DC` | downstream connection termination | The **client** closed the connection first | client timeouts, cancelled requests |
| `URX` | upstream retry limit exceeded | Retries were attempted and all failed | the underlying failure, plus the retry policy |
| `DI` | delay injected | A fault-injection delay held the request | `VirtualService` `fault.delay` |
| `RL` | rate limited | The local rate limit filter rejected the request (status `429`) | rate limit configuration |
| `RLSE` | rate limit service error | The rate limit service returned an error | the rate limit service |
| `DPE` / `UPE` | protocol error | The downstream request / upstream response had an HTTP protocol error | protocol mismatch, a port treated as the wrong protocol |

A few terms in the table need a definition. A **circuit breaker** is a limit on connections or queued requests to a destination; when the limit is full, the proxy rejects new requests instead of sending them. mTLS (mutual Transport Layer Security) means both sides of a connection present a certificate, so the connection is encrypted and both identities are checked. A **network policy** is a Kubernetes object that blocks traffic between pods at the network level.

## Two reading aids

The table is easier to remember as a model than as a list. Two patterns do most of the work, and one special case saves the most time.

### The first letter names the direction

`U` flags are about the **upstream**, the destination the proxy was trying to reach. `D` flags are about the **downstream**, the client. `N` flags are about neither: the proxy could not decide where to go at all.

### The order shows how far the request got

Read the main flags in this order, from "never left" to "left and never came back":

```text
   NR   nothing matched                    - never chose a destination
   NC   chose one that does not exist      - a name with nothing behind it
   UH   it exists, nothing healthy in it   - a cluster with no endpoints
   UO   refused by our own limits          - the proxy declined to try
   UF   tried to connect, failed           - the network or the handshake
   UC   connected, then lost it            - it started and did not finish
   UT   connected, no answer in time       - it started and never finished
```

A flag is a position on that path, and the position tells you which layer to investigate. `NC` and `UH` point at configuration. `UF` points at connectivity or the TLS handshake. `UC` and `UT` point at how the upstream behaves.

### A dash is a real answer

`-` means no proxy-level error happened. If the status is still an error, the application produced it, and the investigation goes back to the application. This is the biggest time saver in this module: it stops an Istio investigation that was never going to find anything.

Two more flags need care. `UO` is not an outage: upstream overflow means your own `connectionPool` settings rejected the request, and the destination may be completely idle. `DC` is not your failure: the client disconnected first, so the cause is a client timeout, a cancelled request or a user closing a browser tab, and looking for it in the mesh finds nothing.

## The second question: who wrote the line

A request between two pods in the mesh passes two proxies: the client's sidecar proxy on the way out and the destination's sidecar proxy on the way in. Both write a line. Comparing the two answers one question more cheaply than anything else: **did the request arrive?**

| Client's proxy | Destination's proxy | Conclusion |
| --- | --- | --- |
| failure | (nothing) | never arrived: routing, clusters, endpoints, or the connection itself |
| failure | failure | arrived, then failed: destination policy, or the application |
| failure | success | the response path failed: a timeout or a reset after the upstream answered |
| (nothing) | failure | the client wrote no line: it is not in the mesh, or its logging is switched off |

The first row is the most common signature of a `503` you cannot explain, and it is also the signature of an mTLS mismatch. A missing line is evidence, but you only get that evidence if you go and look for it.

Before you read failures, see what a successful request looks like from both ends. Send one request, then read the newest line on each side:

<!-- astrona:playground:renew -->

```sh
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -X POST http://notification-service/notify
echo '--- client ---'
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
echo '--- destination ---'
kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy --tail=1
```

You should see something like:

```text
--- client ---
[...] "POST /notify HTTP/1.1" 200 - via_upstream - ... "notification-service" "10.244.0.12:8084" outbound|80||notification-service.accesslog-demo.svc.cluster.local ...
--- destination ---
[...] "POST /notify HTTP/1.1" 200 - via_upstream - ... "notification-service" "10.244.0.12:8084" inbound|8084|| ...
```

It is the same request, with the same status and the same flag, but a different **upstream cluster**. The client's proxy logged `outbound|80||…`, and the destination's proxy logged `inbound|8084||`. That field tells you which side of a connection a line came from, even when you see the line out of context in a log system.

## The same idea in metrics

Istio's metrics make the same client-or-server split with the `reporter` label, which names the proxy that reported the metric: `source` is the client's proxy and `destination` is the destination's proxy. A log line shows one case. A metric can show that something has been happening for twenty minutes and only the client's proxy sees it. The reasoning is the same.

## Summarising a window

One line is a case; many lines are a pattern. A count of flags over a window of traffic is the fastest way to see which failure is most common. Count the flags in the `tester` pod's last 200 lines:

```sh
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=200 \
  | awk '{print $6}' | sort | uniq -c | sort -rn
```

Field `$6` is the flag in the default format. On a healthy playground the count shows only `-`. Here is how to read the shape of a count on a real cluster:

| Count | Reading |
| --- | --- |
| mostly `-`, a few `UT` | healthy, with some slow requests |
| a wall of `UF` | connectivity or mTLS, probably to one destination |
| mixed `-` and `UO` | capacity: your own limits are rejecting load |
| all `NC` | configuration: a route names something that does not exist |
| all `-` with `5xx` statuses | not Istio: the application is failing |

Practise the last row. On an Istio cluster the reflex is to blame the mesh, and this count shows you when not to.

You now have a model for the flags: the first letter gives the direction, the position on the path gives the layer, and a `-` sends you back to the application. You also know to ask which proxy wrote a line, and that a line missing on the destination is evidence. The open question is what these flags look like when you cause them yourself, starting with the failures that the client's proxy decides.

## Common pitfalls

> [!WARNING]
> - **Treating `-` as "no information".** It means no proxy-level error, which points at the application.
> - **Confusing `UO` with an outage.** Upstream overflow is your own connection pool rejecting the request; the destination may be idle.
> - **Chasing `DC` in the mesh.** The client disconnected first. Look at the client.
> - **Reading only the client's log.** Anything enforced on the way in, such as authorization or an mTLS refusal, is explained on the destination. The client's line for a `403` looks ordinary.
> - **Memorising flags instead of the model.** The first letter and the position on the path give you the layer, and the layer is what you need.
> - **Counting flags from both proxies at once.** Client and destination lines describe different halves of the request; mixing them gives a meaningless count.
