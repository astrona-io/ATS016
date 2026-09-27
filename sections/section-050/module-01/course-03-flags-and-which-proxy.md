# Part 3 — Flags, And Which Proxy Wrote The Line

> Prerequisite: [Part 2 — The Anatomy Of A Line](./course-02-anatomy-of-a-log-line.md). Next: [Part 4 — Producing Each Failure On Demand](./course-04-producing-each-failure.md).

Field ④ is two or three characters long and carries more diagnostic weight than everything else on the line combined. This part turns the flag list into a model you can reason from, and then adds the second axis that doubles its value: *which proxy* wrote the line.

## The flags

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

## Two reading aids

The table is easier to hold as a model than as a list, and two patterns do most of the work.

**The prefix names the direction.** `U*` is **upstream** — a statement about the destination the proxy was trying to reach. `D*` is **downstream** — a statement about the client. `N*` is neither: the proxy could not decide where to go at all.

**Within `U*`, the order is how far the request got.**

```text
   NR   nothing matched                    ─ never chose a destination
   NC   chose one that does not exist      ─ a name with nothing behind it
   UH   it exists, nothing healthy in it   ─ a destination with no members
   UO   refused by our own limits          ─ we declined to try
   UF   tried to connect, failed           ─ the network or the handshake
   UC   connected, then lost it            ─ it started and did not finish
   UT   connected, no answer in time       ─ it started and never finished
```

Reading a flag as a *position on that path* tells you which layer to investigate without memorising any individual entry. `NC` and `UH` are configuration. `UF` is connectivity or TLS. `UC` and `UT` are the upstream's behaviour.

**And `-` is a real answer.** It means no proxy-level error occurred, which for an error status hands the investigation back to your application. That is the single most time-saving reading in this module, because it stops an Istio investigation that was never going to find anything.

Two cases deserve care:

- **`UO` is not an outage.** Upstream overflow means *your own* `connectionPool` configuration rejected the request. The destination may be completely idle.
- **`DC` is not your failure.** The client disconnected first. Chasing it in the mesh finds nothing; the cause is a client timeout, a cancelled request, or a user closing a tab.

## The second axis: who logged it

A request crosses two proxies — the client's sidecar on the way out and the destination's on the way in. Both log. Comparing the two answers a question nothing else answers as cheaply: **did the request arrive?**

```text
   client proxy          destination proxy       conclusion
   ────────────          ─────────────────       ──────────
   failure               (nothing)               never arrived — routing, clusters,
                                                 endpoints, or the connection itself
   failure               failure                 arrived, then failed — destination
                                                 policy, or the application
   failure               success                 the response path failed — a timeout
                                                 or a reset after the upstream answered
   (nothing)             failure                 the client never logged: it is not in
                                                 the mesh, or logging is scoped away
```

The first row is the signature [module 040-02](../../section-040/module-02/course-01-who-answered-with-503.md) used and the one [module 050-02](../module-02/course.md) works in detail. The absence of a line is evidence, and it is evidence you only get by going to look for it.

## The healthy pair, for comparison

Before reading failures in [Part 4](./course-04-producing-each-failure.md), see what a successful request looks like from both ends. The differences are as informative as the similarities.

> [!TIP]
> **Try it — one request, two proxies**
>
> ```sh
> kubectl -n accesslog-demo exec deploy/tester -- \
>   curl -s -o /dev/null -X POST http://notification-service/notify
> echo '--- client ---'
> kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
> echo '--- destination ---'
> kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy --tail=1
> ```
>
> Expect something like:
>
> ```text
> --- client ---
> [...] "POST /notify HTTP/1.1" 200 - via_upstream - ... "notification-service" "10.244.0.12:8084" outbound|80||notification-service.accesslog-demo.svc.cluster.local ...
> --- destination ---
> [...] "POST /notify HTTP/1.1" 200 - via_upstream - ... "notification-service" "10.244.0.12:8084" inbound|8084|| ...
> ```
>
> Same request, same status, same flag — and a different **upstream cluster**. The client logged `outbound|80||…`, the destination logged `inbound|8084||`. That field is how you tell at a glance which side of a connection a line came from, even out of context in a log aggregator, and it is the naming convention from [module 040-01 Part 3](../../section-040/module-01/course-03-clusters-and-endpoints.md) doing double duty.

## Reporter, in metrics

The same client/server distinction exists in Istio's metrics as the `reporter` label — `source` and `destination` — which [module 060-02](../../section-060/module-02/course.md) uses to spot the same asymmetry over time rather than per request. Logs give you the individual case; metrics give you "this has been happening for twenty minutes and only the client sees it". The reasoning is identical.

## Summarising a window

One line is a case. Many lines are a pattern, and a flag tally over a window is the fastest way to see which failure dominates.

```sh
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=200 \
  | awk '{print $5}' | sort | uniq -c | sort -rn
```

Field 5 is the flag in the default format. What the shape tells you:

| Tally | Reading |
| --- | --- |
| mostly `-`, a few `UT` | healthy with occasional slow requests |
| a wall of `UF` | connectivity or mTLS — one destination, probably |
| mixed `-` and `UO` | capacity: your own limits are rejecting load |
| all `NC` | configuration: a route names something that does not exist |
| all `-` with 5xx statuses | not Istio. The application is failing |

The last row is worth rehearsing, because the reflex on an Istio cluster is to suspect the mesh.

> [!WARNING]
> **Pitfalls in reading flags**
>
> - **Treating `-` as "no information".** It means no *proxy-level* error, which is a positive finding pointing at the application.
> - **Confusing `UO` with an outage.** Upstream overflow is your own connection pool rejecting the request; the destination may be idle.
> - **Chasing `DC` in the mesh.** The client disconnected first. Look at the client.
> - **Reading only the client's log.** Anything enforced inbound — authorization, mTLS refusal — is explained on the destination. The client's line for a `403` looks unremarkable.
> - **Memorising flags instead of the model.** Prefix plus position along the path gives you the layer, which is what you actually need.
> - **Tallying flags across both proxies at once.** Client and destination lines describe different halves of the request; mixing them produces a meaningless histogram.

> *A flag has two axes: what failed, and on which side of the connection the line was written — neither is enough alone.*

## Reference

- [Envoy response flags](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage#config-access-log-format-response-flags) — the complete list with precise definitions, including the ones this table omits.
- [Istio access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — the default format and field order.
- [Istio standard metrics](https://istio.io/latest/docs/reference/config/metrics/) — the `reporter` and `response_flags` labels, the metrics counterpart of this part.
- [Circuit breaking](https://istio.io/latest/docs/tasks/traffic-management/circuit-breaking/) — the `connectionPool` settings behind `UO`, produced deliberately in Part 4.
