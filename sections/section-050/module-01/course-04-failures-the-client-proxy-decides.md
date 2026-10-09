# Failures The Client's Proxy Decides

Astronaut, reading a flag table is not the same as recognising a flag at three in the morning. In this part you run three training drills: you make signals fail on purpose and identify each failure from its flight log line alone. The three are a timeout (`UT`), a circuit breaker rejection (`UO`) and a routing miss (`NR`). All three are decided by the communications officer on the **sending** ship, the tester's sidecar proxy.

The drills get in each other's way if you leave them in place, so follow the order. Each drill removes the one before it.

## UT: a route timeout

A **timeout** is giving up on a late reply. A `VirtualService`, the flight plan for a beacon, can carry a `timeout`. It can also carry a fault-injection `delay`, a training drill in which the proxy holds every signal back on purpose. The idea of this drill is to set a delay longer than the timeout, so you get a timeout without needing a slow service.

The delay is added by the **client's** own proxy, before it sends the request on.

<!-- astrona:playground:renew -->

### A 5-second delay against a 1-second timeout

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
    - fault:
        delay:
          fixedDelay: 5s
          percentage:
            value: 100
      timeout: 1s
      route:
        - destination:
            host: notification-service
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

Then check the result. Send one request and read the tester's newest flight log line:

```sh
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
```

The expected result looks like this:

```text
504
[...] "POST /notify HTTP/1.1" 504 UT response_timeout - "-" 0 24 1000 - ... "-" outbound|80||notification-service.accesslog-demo.svc.cluster.local ...
```

Three fields tell the whole story when a route timeout fires. The status is `504`, not `503`: a timeout has its own code. The flag is `UT`, with the details `response_timeout`. And the duration is about `1000` milliseconds: **the timeout, not the delay**, because the proxy gave up after one second instead of waiting five.

Be careful with this drill. In Envoy, the fault filter runs **before** the router, and the router is the part that starts the route timeout. So a delay and a timeout on the same rule may never meet: the authors of this course measured exactly that in a lab, where the result was a `200` with the flag `DI` (delay injected) after about five seconds, and no `UT`. If you get that result, the timeout did not fire. A real slow service behind the route, not a delay on the same rule, is what reliably produces `UT`.

## UO: a circuit breaker

A **circuit breaker** closes the docking bay when too many ships queue. `UO` stands for **u**pstream **o**verflow: the proxy refused to send the request, because a connection pool limit in a `DestinationRule` was already full. Your own configuration rejected it; the destination did not fail. This is the flag people most often misread as an outage.

To produce it you need two things at once: limits low enough to hit, and enough requests at the same time to hit them.

### A pool of one, and thirty requests at once

First remove the flight plan from the timeout drill. Its 5-second delay would slow every request down and hide the effect completely:

```sh
kubectl -n accesslog-demo delete virtualservice notification
```

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
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=30 | grep -c ' UO '
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=30 | grep ' UO ' | head -1
```

You should see something like:

```text
12
[...] "POST /notify HTTP/1.1" 503 UO upstream_overflow - "-" 0 81 0 - ... "-" outbound|80||notification-service...
```

Some of the thirty requests were rejected. The exact number depends on timing and changes from run to run, which is typical for a limit on requests at the same time. Look at the duration: `0` milliseconds. The tester's proxy refused the request at once, without contacting the destination. That is how you tell `UO` apart from a real upstream problem on a latency graph.

The three `connectionPool` fields do different jobs. `maxConnections` limits the number of open TCP (Transmission Control Protocol) connections. `http1MaxPendingRequests` limits the requests waiting in a queue for a connection. `maxRequestsPerConnection` forces a new connection for every request. Set to `1`, they make the limit easy to reach; in production they are a deliberate way to shed load.

## NR: nothing matched

`NR` means the proxy had no route for this request. The most direct way to produce it is to address a host the proxy has no route for. You do that by changing the `Host` header, not the address: the proxy picks a route by the `Host` header.

### A request addressed to nowhere

Send a request to the `notification-service` address, but with the `Host` header `nosuchhost.local`:

```sh
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -H "Host: nosuchhost.local" http://notification-service/notify
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
```

You should see something like:

```text
404
[...] "POST /notify HTTP/1.1" 404 NR route_not_found - "-" 0 0 0 - "-" "curl/8.4.0" "..." "nosuchhost.local" "-" - - ...
```

A `404`, not a `503`, and the difference matters. The connection was made and the proxy's listener accepted it; only the routing step failed, so there was no upstream that could be unavailable. The authority field reads `nosuchhost.local`, which proves that the `Host` header, not the destination address, is what routing matched against.

In production, `NR` usually has a less exotic cause. Often it is a Service port with no declared protocol, so the proxy built no HTTP route for it. Or it is a `VirtualService` bound to a gateway while the traffic stays inside the mesh.

## What the three have in common

Look at the upstream host field on all three lines: it is `-` every time. None of these requests ever contacted the destination. The tester's own proxy made each decision, from its own configuration, so the destination's flight log has no line for them.

| Flag | Status | Duration | Upstream host |
| --- | --- | --- | --- |
| `UT` | `504` | about the timeout | `-` |
| `UO` | `503` | `0` | `-` |
| `NR` | `404` | `0` | `-` |

The `notification` `DestinationRule` with the pool of one is still applied. Leave it for now; the next drill removes it at the end.

## Common pitfalls

> [!WARNING]
> - **Leaving drill configuration behind.** Fault injection and tight connection pools stay in effect until you delete them. Remove them in the same session.
> - **Stacking the drills.** A 5-second injected delay hides a circuit breaker completely. Apply one at a time.
> - **Putting a fault delay and a timeout on the same rule and expecting `UT`.** The fault filter runs before the router, so the timeout may never see the delay.
> - **Expecting an exact `UO` count.** It depends on timing and changes every run. The flag being there is the finding, not the number.
> - **Assuming `UT` means the upstream is slow.** Compare the duration with the upstream service time before you blame a backend.
> - **Treating a `404` as a bug in your routing rule.** `NR` often means the `Host` header or the port protocol, not the rule you were editing.

> *All three of these failures were decided on the sending ship: the destination never saw them.*

## Your mission: Scope The Logs, Bound The Latency, Name The Flag

You can now switch on and scope the flight log, and read a timeout from its flag. The mission asks you to scope logging to one namespace with a `Telemetry` object, bound a slow dependency with a 2-second timeout, and find the `UT` flag it produces.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-050-01
```

Then start the mission:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-01/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-016-lab-050-01
astrona start ats-016-playground-050-01
```
