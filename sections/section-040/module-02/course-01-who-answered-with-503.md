# Part 1 — Who Answered With 503

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — Walking The Chain](./course-02-walking-the-chain.md).

The first useful question about a `503` is not *why* but *who*. Until you know whether the proxy or the application produced it, every theory is a guess — and the two live in different systems, with different logs, fixed by different people. This part answers it in one command and then reads the answer properly.

## The symptom, and what it already rules out

> [!TIP]
> **Try it — the failure**
>
> ```sh
> kubectl -n fivezerothree-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
> kubectl -n fivezerothree-demo get pods
> ```
>
> Expect something like:
>
> ```text
> 503
> NAME                                      READY   STATUS    RESTARTS   AGE
> notification-service-v1-6c9f8b7d5-x2kqp   2/2     Running   0          6m
> tester-6d9f7b8c5-hj4kz                    2/2     Running   0          6m
> ```
>
> A `503` against a `2/2 Running` destination with no restarts. That combination eliminates the obvious explanations before you spend any time on them: the application is up, it has a sidecar, and nothing has crashed and come back. Whatever refused this request did so somewhere between the two pods — or before the request ever left the first one.

`2/2` is doing real work in that reading. A `1/1` pod would have pointed straight at [module 030-03](../../section-030/module-03/course.md), because a destination with no sidecar cannot participate in mesh routing at all.

## Where a 503 can come from

Four different components can produce the same three digits:

```text
   tester app ──▶ tester's sidecar ──▶ network ──▶ destination sidecar ──▶ destination app
                       │                                  │                      │
                       │                                  │                      └─ the app itself
                       │                                  │                         returned 503
                       │                                  └─ inbound policy or
                       │                                     the app connection failed
                       └─ no cluster / no endpoints /
                          upstream never reached
```

Distinguishing them by inspection is impossible: the status code carries no origin. Envoy solves this by writing an **access log line** for every request it handles, and putting in it a short code — the **response flag** — that says why the request ended the way it did.

The `demo` profile used by this playground enables access logging by default. In a production-profile install it is usually off, and turning it on is [module 050-01](../../section-050/module-01/course.md)'s first topic.

## The flags in the 503 family

| Flag | Name | What it means | Where to look next |
| --- | --- | --- | --- |
| `NC` | no cluster | the route named a cluster that does not exist | `DestinationRule` subsets, host names |
| `UH` | no healthy upstream host | the cluster exists and has no usable endpoints | Service selector, pod readiness, subset labels, ejections |
| `NR` | no route | nothing matched the request | `Host` header, port protocol, `VirtualService` binding |
| `UF` | upstream connection failure | could not establish a connection at all | mTLS mismatch, wrong port, network policy |
| `UC` | upstream connection termination | the connection was dropped mid-request | application crash, protocol mismatch |
| `-` | *(none)* | no proxy-level error | the **application** produced the status |

Two reading aids make this a model rather than a list. The `U` prefix means **upstream** — a statement about the destination — and the flags are roughly ordered by how far the request got: `NC` never found a destination, `UH` found one with nothing in it, `UF` tried to connect and failed, `UC` connected and lost it.

And the last row is the one that saves the most time. A `503` with flag `-` is **your service's own answer**, faithfully relayed. No amount of Istio debugging will explain it, and the investigation belongs in the application's logs.

## Reading the line

> [!TIP]
> **Try it — the proxy's account of the request**
>
> ```sh
> kubectl -n fivezerothree-demo logs deploy/tester -c istio-proxy --tail=5
> ```
>
> Expect something like:
>
> ```text
> [2026-09-27T09:31:44.812Z] "POST /notify HTTP/1.1" 503 NC no_healthy_upstream - "-" 0 19 0 - "-" "curl/8.4.0" "b1f0..." "notification-service" "-" - - 10.96.44.31:80 10.244.0.9:41234 - default
> ```
>
> Read it left to right and stop at the fourth field:
>
> ```text
>   "POST /notify HTTP/1.1"   503      NC       no_healthy_upstream    ...   "-"
>    the request              status   FLAG     response code details        upstream host
> ```
>
> `NC` says this came from the proxy and names the reason: there was no usable cluster to send it to. The exact flag can differ by Istio version and by the precise state — `UH` appears in closely related cases — which is why you **read the flag you get** rather than reciting one from memory.

Two more fields on that line carry weight:

- **`response code details`** (`no_healthy_upstream` here) is Envoy's own longer explanation, and for some failures — notably authorization — it is the entire answer.
- **The upstream host field** is `-`. That means no connection was ever attempted. Compare with a successful request, where it holds an address like `10.244.0.12:8084`. An address there proves the proxy got as far as talking to something.

## The other log that is empty

This is the half of the evidence people forget to gather: check the **destination's** proxy for the same request.

```sh
kubectl -n fivezerothree-demo logs deploy/notification-service-v1 -c istio-proxy --tail=5
```

Nothing corresponding appears. That absence is not a gap in the evidence — it *is* evidence, and it is decisive:

| Client log | Destination log | Means |
| --- | --- | --- |
| failure | **nothing** | the request never arrived. Routing, clusters, endpoints, or the connection itself. |
| failure | failure | it arrived and failed there. Inbound policy, or the application. |
| success | failure | rare; a problem on the response path. |

Here the client failed and the destination saw nothing, so the entire investigation stays on the **sending** side — which is exactly where [Part 2](./course-02-walking-the-chain.md) walks.

## What the flag has already told you

Before running a single `proxy-config` command, the log has narrowed the problem to one stage of [module 040-01's](../module-01/course.md) four:

```text
   NR  → stage 2, route        nothing matched
   NC  → stage 3, cluster      the named cluster does not exist
   UH  → stage 4, endpoint     the cluster is empty
   UF  → beyond stage 4        connection refused at the far end (section 050-02)
   -   → not Istio             the application answered
```

That is why "read the flag first" is the rule and not a preference. Walking the chain from stage one with no flag is four commands; walking it with a flag is one.

> [!WARNING]
> **Pitfalls in identifying the source of a 503**
>
> - **Reading the application log first.** For this class of failure the request never reaches the application; its log is empty and proves nothing.
> - **Ignoring the response flag.** `NC`, `UH`, `UF` and `UC` point at four different layers, and `-` points out of Istio entirely. Guessing without it wastes more time than any other mistake in this module.
> - **Memorising one flag for "missing subset".** The exact flag varies with Istio version and state. Read what you actually get, and use the table to interpret it.
> - **Failing to check the destination's log.** The absence of a matching line is half the diagnosis.
> - **Assuming a `503` with a healthy pod means the application is down.** `2/2 Running` plus `503` is the signature of a routing fault, not an application fault.
> - **Expecting access logs to be enabled.** The `demo` profile turns them on; many production installs do not.

> *The status code says a request failed; the response flag says who failed it, and that is the only question worth asking first.*

## Reference

- [Envoy access logging — response flags](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage#config-access-log-format-response-flags) — the complete flag list with precise definitions.
- [Istio default access log format](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — every field in the line above, in order.
- [Common problems — 503 errors](https://istio.io/latest/docs/ops/common-problems/network-issues/) — symptom-first index for the variants this module does not cover.
- `kubectl logs <pod> -c istio-proxy --tail=20 -f` — following a proxy's log while you reproduce a failure; the fastest way to attribute a specific request.
