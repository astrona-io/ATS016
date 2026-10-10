# Failures The Client's Proxy Decides

Reading a table of flags is not the same as recognising a flag during an incident. In this part you make requests fail on purpose and identify each failure from its access log line alone. The three failures are a route timeout (`UT`), a circuit breaker rejection (`UO`) and a routing miss (`NR`). The client's sidecar proxy, here the `tester` pod's proxy, decides all three from its own configuration.

The examples get in each other's way if you leave them in place, so follow the order. Each step removes the configuration of the one before it.

## UT: a route timeout

A `VirtualService` is the Istio resource that tells the sidecar proxies how to route requests for a host. Its `timeout` field sets how long the client's proxy waits for the upstream to answer before it gives up. To see the timeout fire, you need an upstream that is slower than the timeout. In the playground, nginx forwards any request for the path `/slow` to a small HTTP server in the same pod, which waits five seconds before it answers. A timeout of one second on the route is enough.

<!-- astrona:playground:renew -->

Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: accesslog-demo
spec:
  hosts:
    - notification-service
  http:
    - timeout: 1s
      route:
        - destination:
            host: notification-service
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

Then check the result. Send one request to `/slow` and read the `tester` pod's newest access log line:

```sh
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/slow
sleep 2
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
```

The request returns `504`, and the newest line in the `tester` pod's log is the `POST /slow` request, with the status `504`, the flag `UT` and the details `response_timeout`.

Three fields tell the whole story. The status is `504`, not `503`, because a timeout has its own status code. The flag is `UT`, with the details `response_timeout`. And the duration is about `1000` milliseconds: **the timeout, not the five-second wait**, because the client's proxy gave up after one second. The upstream host is an address, because the request did reach the destination; the client's proxy simply stopped waiting for the answer. The destination's proxy also writes a line for this request, usually with the flag `DC`, because the client's proxy closed the connection first.

You may have seen a timeout example built with fault injection instead: a `fault.delay` of five seconds and a `timeout` of one second on the same route rule. Fault injection is a `VirtualService` feature that makes the proxy delay or fail requests on purpose. That combination does not produce `UT`. In Envoy, the fault filter runs **before** the router, and the router starts the route timeout only when the request reaches it. So the delay is over before the timeout clock starts, and the request ends with the flag `DI` (delay injected) instead of `UT`. A slow upstream behind the route, as in this example, is what produces `UT`.

## UO: a circuit breaker

`UO` stands for upstream overflow. It means the client's proxy refused to send the request, because a connection pool limit in a `DestinationRule` was already full. A `DestinationRule` defines what happens to traffic for a host after routing, including connection pool limits. Your own configuration rejected the request; the destination did not fail. This is the flag people most often misread as an outage.

To produce it you need two things at once: limits low enough to hit, and enough requests at the same time to hit them. First remove the `VirtualService` from the timeout example, so that its timeout does not change the results:

```sh
kubectl -n accesslog-demo delete virtualservice notification
```

The `DestinationRule` below allows one connection, one waiting request and one request per connection.

Save this as `destinationrule-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification
  namespace: accesslog-demo
spec:
  host: notification-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
```

Apply it:

```sh
kubectl apply -f destinationrule-notification.yaml
```

Then check the result. Send thirty requests at the same time, count the `UO` lines, and print one of them:

```sh
kubectl -n accesslog-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 30); do curl -s -o /dev/null -X POST http://notification-service/notify & done; wait'
sleep 2
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=30 | grep -c ' UO '
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=30 | grep ' UO ' | head -1
```

The first command prints how many of the last thirty lines carry `UO`, and the second prints one of them: a `503` with the flag `UO` and the details `upstream_overflow`. Some of the thirty requests were rejected. The exact number depends on timing and changes from run to run, which is normal for a limit on requests at the same time. Look at the duration, `0` milliseconds, and the upstream host, `-`. The `tester` pod's proxy refused the request at once, without contacting the destination. That is how you tell `UO` apart from a real upstream problem on a latency graph.

The three `connectionPool` fields do different jobs. `maxConnections` limits the number of open TCP (Transmission Control Protocol) connections to the destination. `http1MaxPendingRequests` limits the requests that wait in a queue for a free connection. `maxRequestsPerConnection` sets how many requests one connection carries before the proxy closes it. Set to `1`, they make the limit easy to reach; in production they are a deliberate way to shed load.

## NR: no route matched

`NR` means the client's proxy found no route for the request. A `VirtualService` whose rules only match some paths produces it reliably: a request for any other path finds the host but no matching rule. The `VirtualService` below routes only requests whose path starts with `/reports`.

Save this as `virtualservice-notification-reports-only.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: accesslog-demo
spec:
  hosts:
    - notification-service
  http:
    - match:
        - uri:
            prefix: /reports
      route:
        - destination:
            host: notification-service
```

Apply it:

```sh
kubectl apply -f virtualservice-notification-reports-only.yaml
```

Then check the result. Send one request to `/notify` and read the newest line:

```sh
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
sleep 2
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
```

You should see something like:

```text
404
[2026-10-09T22:25:26.047Z] "POST /notify HTTP/1.1" 404 NR route_not_found - "-" 0 0 0 - "-" "curl/8.22.0" "dfcc5add-1517-9864-b6b5-ddccd8150d28" "notification-service" "-" - - 10.96.92.93:80 10.244.0.9:57964 - -
```

The status is `404`, not `503`, and the difference matters. The proxy's listener accepted the connection, and only the routing step failed, so there was no upstream that could be unavailable. The upstream host and the upstream cluster are both `-`, because the proxy never chose a destination.

In production, `NR` usually has a less obvious cause. Often it is a Service port with no declared protocol, so the proxy built no HTTP route for it. Sometimes it is a `VirtualService` bound to a gateway while the traffic stays inside the mesh, or a match rule that is narrower than the author intended.

## What the three have in common

Put the three lines next to each other:

| Flag | Status | Duration | Upstream host |
| --- | --- | --- | --- |
| `UT` | `504` | about the timeout | an address |
| `UO` | `503` | `0` | `-` |
| `NR` | `404` | `0` | `-` |

The client's own proxy made all three decisions, from its own configuration. `UO` and `NR` never contacted the destination at all, so the destination's proxy has no line for them. `UT` did reach the destination, but the decision to give up was still made on the client's side, by the route timeout. In every case, the place to look is the configuration that the client's proxy holds for this host.

You can now recognise a timeout, a circuit breaker rejection and a routing miss from one log line each, and you know that the client's proxy decides all three. The `notification` `DestinationRule` with the pool of one and the `VirtualService` that matches only `/reports` are still applied; they are removed later. The open question is a failure that the client's proxy cannot explain at all, because another proxy made the decision.

## Common pitfalls

> [!WARNING]
> - **Leaving test configuration behind.** Timeouts, match rules and tight connection pools stay in effect until you delete them. Remove them in the same session.
> - **Stacking the examples.** A route that matches nothing hides a circuit breaker completely. Apply one at a time.
> - **Putting a fault delay and a timeout on the same rule and expecting `UT`.** The fault filter runs before the router, so the timeout never sees the delay.
> - **Expecting an exact `UO` count.** It depends on timing and changes every run. The flag being there is the finding, not the number.
> - **Assuming `UT` means the upstream is slow.** Compare the duration with the upstream service time before you blame a backend.
> - **Treating every `404` as an application error.** `NR` comes from the proxy: check the `Host` header, the port protocol and the `VirtualService` match rules.

## Your mission: Scope The Logs, Bound The Latency, Name The Flag

You can now scope the access log with a `Telemetry` object and read a timeout from its flag. The graded lab asks you to switch on access logging for one namespace with a `Telemetry` object, bound a slow dependency with a two-second route timeout, and find the `UT` flag it produces.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-050-01
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-01/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-050-01
astrona start ats-016-playground-050-01
```
