# Part 4 — Producing Each Failure On Demand

> Prerequisite: [Part 3 — Flags, And Which Proxy Wrote The Line](./course-03-flags-and-which-proxy.md). Next: [the module landing page](./course.md), then [module 050-02](../module-02/course.md).

Reading a flag table is not the same as recognising a flag at three in the morning. This part produces four failures deliberately — a timeout, a circuit breaker rejection, a routing miss and an authorization denial — and identifies each from its log alone. Each one is applied, observed, and then removed before the next.

The four interfere with each other if left in place, so follow the order and let each checkpoint clean up after itself.

## UT — a route timeout

A `VirtualService` can carry both a `timeout` and a fault-injection `delay`. Setting a delay longer than the timeout produces a guaranteed timeout without needing a genuinely slow service.

The mechanism matters for reading the result: **the delay is injected by the client's own proxy**, before the request is sent. So the destination never sees this request at all, and its log stays empty.

> [!TIP]
> **Try it — a 5-second delay against a 1-second timeout**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: notification
>   namespace: accesslog-demo
> spec:
>   hosts:
>     - notification-service
>   http:
>     - fault:
>         delay:
>           fixedDelay: 5s
>           percentage:
>             value: 100
>       timeout: 1s
>       route:
>         - destination:
>             host: notification-service
> EOF
> kubectl -n accesslog-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
> kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
> ```
>
> Expect something like:
>
> ```text
> 504
> [...] "POST /notify HTTP/1.1" 504 UT response_timeout - "-" 0 24 1000 - ... "-" outbound|80||notification-service.accesslog-demo.svc.cluster.local ...
> ```
>
> Three fields tell the whole story. Status `504`, not `503` — a timeout has its own code. Flag `UT` with details `response_timeout`. And the duration field is roughly `1000` milliseconds: **the timeout, not the delay**, because the proxy gave up at one second rather than waiting five. The upstream host field is `-`, confirming nothing was ever contacted.

## UO — a circuit breaker

`UO` stands for **u**pstream **o**verflow: the proxy refused to send the request because a connection pool limit in a `DestinationRule` was already at its ceiling. It is a rejection *by your own configuration*, not a failure of the destination — the flag people most often misread as an outage.

Producing it needs two things at once: limits low enough to hit, and enough concurrency to hit them. Note that the `VirtualService` from the previous checkpoint has to go first, or its 5-second delay will serialise everything and mask the effect entirely.

> [!TIP]
> **Try it — a pool of one, and thirty simultaneous requests**
>
> ```sh
> kubectl -n accesslog-demo delete virtualservice notification
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: DestinationRule
> metadata:
>   name: notification
>   namespace: accesslog-demo
> spec:
>   host: notification-service
>   trafficPolicy:
>     connectionPool:
>       tcp:
>         maxConnections: 1
>       http:
>         http1MaxPendingRequests: 1
>         maxRequestsPerConnection: 1
> EOF
> kubectl -n accesslog-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 30); do curl -s -o /dev/null -X POST http://notification-service/notify & done; wait'
> kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=30 | grep -c ' UO '
> kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=30 | grep ' UO ' | head -1
> ```
>
> Expect something like:
>
> ```text
> 12
> [...] "POST /notify HTTP/1.1" 503 UO upstream_overflow - "-" 0 81 0 - ... "-" outbound|80||notification-service...
> ```
>
> Some number of the thirty were rejected — the exact count varies with timing and differs between runs, which is itself characteristic of a concurrency limit. Note the duration: `0` milliseconds. The request was refused instantly, without any attempt to contact the destination, which is what distinguishes `UO` from a genuine upstream problem in a latency graph.

The three fields in that `connectionPool` do different jobs: `maxConnections` caps concurrent TCP connections, `http1MaxPendingRequests` caps requests queued waiting for one, and `maxRequestsPerConnection` forces a new connection per request. Set to `1` they make the limit trivially reachable; in production they are a deliberate load-shedding policy.

## NR — nothing matched

`NR` means the proxy had no route for this request. The most direct way to produce it is to address a host the proxy has no virtual host for — which, from [module 040-01 Part 2](../../section-040/module-01/course-02-routes.md), means overriding the `Host` header rather than changing the address.

> [!TIP]
> **Try it — a request addressed to nowhere**
>
> ```sh
> kubectl -n accesslog-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -H "Host: nosuchhost.local" http://notification-service/notify
> kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
> ```
>
> Expect something like:
>
> ```text
> 404
> [...] "POST /notify HTTP/1.1" 404 NR route_not_found - "-" 0 0 0 - "-" "curl/8.4.0" "..." "nosuchhost.local" "-" - - ...
> ```
>
> A `404`, not a `503` — a distinction worth keeping. The connection was made and the listener accepted it; only the routing step failed, so there was no upstream to be unavailable. The authority field reads `nosuchhost.local`, which is the direct evidence that the `Host` header, not the destination address, is what routing matched against.

In production the same flag usually means something less exotic: a port with no declared protocol so no HTTP route was built, or a `VirtualService` bound to a gateway when the traffic is mesh-internal.

## An RBAC denial, on the other proxy

The last failure is different in kind. It happens on the **destination** side, after the request has crossed the network, and the client's log will tell you almost nothing about why.

> [!TIP]
> **Try it — the same request, two very different log lines**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: security.istio.io/v1
> kind: AuthorizationPolicy
> metadata:
>   name: deny-all
>   namespace: accesslog-demo
> spec:
>   selector:
>     matchLabels:
>       app: notification-service
>   action: DENY
>   rules:
>     - {}
> EOF
> sleep 3
> kubectl -n accesslog-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
> echo '--- client ---'
> kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
> echo '--- destination ---'
> kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy --tail=1
> ```
>
> Expect something like:
>
> ```text
> 403
> --- client ---
> [...] "POST /notify HTTP/1.1" 403 - via_upstream - ... "10.244.0.12:8084" outbound|80||notification-service...
> --- destination ---
> [...] "POST /notify HTTP/1.1" 403 - rbac_access_denied_matched_policy[ns[accesslog-demo]-policy[deny-all]-rule[0]] ... inbound|8084||
> ```
>
> Both proxies logged, both show flag `-`, and both are correct: at the connection level nothing went wrong. The client's line looks like an ordinary relay of a `403`. Only the destination's `RESPONSE_CODE_DETAILS` carries `rbac_access_denied_matched_policy[...]`, naming the namespace, the policy and the rule index that refused — the same identifier `istioctl x describe pod` printed in [module 010-02 Part 1](../../section-010/module-02/course-01-what-describe-resolves.md).

This is the case that justifies Part 3's second axis on its own. A flag of `-` on both sides and a `403` in the middle is a failure the flag taxonomy cannot explain; the details field on the *right* proxy can.

## Cleaning up, and reading the whole window

> [!TIP]
> **Try it — removing the failures, and counting what happened**
>
> ```sh
> kubectl -n accesslog-demo delete authorizationpolicy deny-all
> kubectl -n accesslog-demo delete destinationrule notification
> sleep 3
> kubectl -n accesslog-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
> kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=60 \
>   | awk '{print $5}' | sort | uniq -c | sort -rn
> ```
>
> Expect something like:
>
> ```text
> 200
>   31 UO
>   14 -
>    1 UT
>    1 NR
> ```
>
> Traffic works again, and the tally is a compact history of this part. On a real incident the same command over a longer window is the fastest way to see which failure dominates — and, from Part 3's table, a mix of `-` and `UO` reads as a capacity problem while a wall of `UF` reads as connectivity or mTLS.

## The four, side by side

| Flag | Status | Duration | Upstream host | Destination logged? |
| --- | --- | --- | --- | --- |
| `UT` | `504` | ≈ the timeout | `-` | no |
| `UO` | `503` | `0` | `-` | no |
| `NR` | `404` | `0` | `-` | no |
| RBAC (`-`) | `403` | small | an address | **yes** |

Read down the last two columns. Three of the four never contacted the destination at all — they are decisions the client's own proxy made, from its own configuration. Only the authorization denial crossed the network. That division is the practical meaning of "which proxy wrote the line", and it decides where you look next before you know anything else.

> [!WARNING]
> **Pitfalls in reproducing and interpreting**
>
> - **Leaving diagnostic configuration behind.** Fault injection, tight connection pools and deny-all policies stay in effect until deleted. Remove them in the same session.
> - **Stacking the experiments.** A 5-second injected delay masks a circuit breaker entirely. Apply one at a time.
> - **Reading only the client's log for a `403`.** The client's line is unremarkable; the destination's details field is the answer.
> - **Expecting an exact `UO` count.** It depends on timing and will differ every run. The presence of the flag is the finding, not the number.
> - **Assuming `UT` means the upstream is slow.** Here the delay was injected locally. Compare duration against upstream service time before blaming a backend.
> - **Treating a `404` as a routing rule bug.** `NR` frequently means the `Host` header or the port protocol, not the rule you were editing.

> *Three of these four failures never reach the destination — which is why the first question about any flag is still "who wrote the line".*

## Reference

- [Fault injection](https://istio.io/latest/docs/tasks/traffic-management/fault-injection/) — `delay` and `abort`, and where in the path each is applied.
- [Circuit breaking](https://istio.io/latest/docs/tasks/traffic-management/circuit-breaking/) — the `connectionPool` fields and what each limits.
- [Authorization policy](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — `DENY`/`ALLOW` evaluation, and the policy identifier in the details field.
- [Envoy response flags](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage#config-access-log-format-response-flags) — for the flags this part did not produce.
