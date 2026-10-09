# Flags, And Which Proxy Wrote The Line

Astronaut, the **response flag** is the short code the communications officer (the sidecar proxy) stamps on a failed signal in the flight log (the access log). It is only two or three characters long, yet it tells you more than the rest of the line put together. This part turns the list of flags into a model you can reason with. Then it adds a second question that doubles their value: *which proxy* wrote the line.

## The flags

Each flag names one way a request can end. The last column says where to look next, so the flag sends you straight to the right object.

| Flag | Name | What it means | Where to look next |
| --- | --- | --- | --- |
| `-` | *(none)* | No proxy-level error. If the status is an error, the **application** produced it | application logs |
| `NR` | no route | Nothing matched the request | `Host` header, port protocol, `VirtualService` binding |
| `NC` | no cluster | The route named a cluster that does not exist | `DestinationRule` subsets, host names |
| `UH` | no healthy upstream host | The cluster exists and has no usable endpoints | Service selector, readiness, subset labels, ejections |
| `UF` | upstream connection failure | Could not establish a connection | mTLS mismatch, wrong port, network policy |
| `UO` | upstream overflow | A circuit breaker rejected it | `DestinationRule` `connectionPool` limits |
| `UT` | upstream request timeout | The route timeout fired | `VirtualService` `timeout`, a slow upstream |
| `UC` | upstream connection termination | The upstream closed mid-request | application crash, protocol mismatch |
| `DC` | downstream connection termination | The **client** gave up first | client timeouts, cancellation |
| `URX` | upstream retry limit exceeded | retries were attempted and all failed | the underlying failure, plus retry policy |
| `RL` / `RLSE` | rate limited | a rate limit filter rejected it | rate limit configuration |
| `DPE` / `UPE` | protocol error | downstream / upstream sent something unparseable | protocol mismatch, a port treated as the wrong protocol |

A few words used in the table: the **upstream** is the destination the proxy sends to, and the **downstream** is the caller. A **cluster** is Envoy's name for a destination squadron, and an **endpoint** is one ship's actual address in it. mTLS (mutual Transport Layer Security) is the secret handshake both ships do before they talk.

## Two reading aids

The table is easier to hold as a model than as a list. Two patterns do most of the work, and one special case saves the most time.

### The first letter names the direction

`U*` flags are about the **upstream**, the destination the proxy was trying to reach. `D*` flags are about the **downstream**, the client. `N*` flags are about neither: the proxy could not decide where to go at all.

### Within the U flags, the order is how far the request got

Read the flags in this order, from "never left" to "left and never came back":

```text
   NR   nothing matched                    ─ never chose a destination
   NC   chose one that does not exist      ─ a name with nothing behind it
   UH   it exists, nothing healthy in it   ─ a destination with no members
   UO   refused by our own limits          ─ we declined to try
   UF   tried to connect, failed           ─ the network or the handshake
   UC   connected, then lost it            ─ it started and did not finish
   UT   connected, no answer in time       ─ it started and never finished
```

A flag is a *position on that path*, and the position tells you which layer to investigate. `NC` and `UH` are configuration. `UF` is connectivity or the handshake. `UC` and `UT` are about how the upstream behaves.

### A dash is a real answer

`-` means no proxy-level error happened. If the status is still an error, the application made it, and the investigation goes back to your application. This is the biggest time saver in this module: it stops an Istio investigation that was never going to find anything.

Two more flags need care:

- **`UO` is not an outage.** Upstream overflow means *your own* `connectionPool` settings rejected the request. The destination may be completely idle.
- **`DC` is not your failure.** The client disconnected first. Looking for it in the mesh finds nothing; the cause is a client timeout, a cancelled request, or a user closing a browser tab.

## The second question: who wrote the line

A signal between two ships passes two communications officers: the client's sidecar on the way out, and the destination's sidecar on the way in. Both write a line. Comparing the two answers one question more cheaply than anything else: **did the request arrive?**

| Client proxy | Destination proxy | Conclusion |
| --- | --- | --- |
| failure | (nothing) | never arrived: routing, clusters, endpoints, or the connection itself |
| failure | failure | arrived, then failed: destination policy, or the application |
| failure | success | the response path failed: a timeout or a reset after the upstream answered |
| (nothing) | failure | the client never logged: it is not in the mesh, or logging is scoped away |

The first row is the most common signature for a `503` you cannot explain, and it is the signature of an mTLS mismatch. A missing line is evidence, but you only get that evidence if you go and look for it.

<!-- astrona:playground:renew -->

### One request, two proxies

Before you read failures, see what a successful request looks like from both ends. Send one request, then read the newest line on each side:

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

Same request, same status, same flag, but a different **upstream cluster**. The client's proxy logged `outbound|80||…`, the destination's proxy logged `inbound|8084||`. That field tells you at a glance which side of a connection a line came from, even when you see it out of context in a log system.

## The same idea in metrics

Istio's metrics make the same client-or-server split with the `reporter` label: which ship filed the report. `source` is the sender, `destination` the receiver. Logs give you one case; metrics tell you "this has been happening for twenty minutes, and only the client sees it". The reasoning is the same.

## Summarising a window

One line is a case. Many lines are a pattern, and a count of flags over a time window is the fastest way to see which failure is most common.

### Count the flags

Count the flags in the tester's last 200 lines:

```sh
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=200 \
  | awk '{print $5}' | sort | uniq -c | sort -rn
```

Field 5 is the flag in the default format. Here is how to read the shape of the count:

| Count | Reading |
| --- | --- |
| mostly `-`, a few `UT` | healthy with occasional slow requests |
| a wall of `UF` | connectivity or mTLS, probably to one destination |
| mixed `-` and `UO` | capacity: your own limits are rejecting load |
| all `NC` | configuration: a route names something that does not exist |
| all `-` with 5xx statuses | not Istio. The application is failing |

Practise the last row. On an Istio cluster the reflex is to blame the mesh, and this count shows you when not to.

## Common pitfalls

> [!WARNING]
> - **Treating `-` as "no information".** It means no *proxy-level* error, which points at the application.
> - **Confusing `UO` with an outage.** Upstream overflow is your own connection pool rejecting the request; the destination may be idle.
> - **Chasing `DC` in the mesh.** The client disconnected first. Look at the client.
> - **Reading only the client's log.** Anything enforced on the way in, like authorization or an mTLS refusal, is explained on the destination. The client's line for a `403` looks ordinary.
> - **Memorising flags instead of the model.** The first letter plus the position on the path gives you the layer, and the layer is what you need.
> - **Counting flags from both proxies at once.** Client and destination lines describe different halves of the request; mixing them gives a meaningless count.

> *A flag has two parts: what failed, and on which side of the connection the line was written. Neither is enough alone.*
