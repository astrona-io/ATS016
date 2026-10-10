# Who Answered With 503

The first useful question about a `503` is not *why* but *who*. Until you know whether a proxy or the application produced it, every theory is a guess. The two live in different places, with different logs, and different people fix them. This part answers the question with one command, and then reads the answer properly.

## The symptom, and what it already rules out

Start with the failure itself and the state of the pods in the namespace. Together they already rule out the obvious explanations. Send one request from the `tester` pod to the `notification-service` Service, then list the pods:

<!-- astrona:playground:renew -->

```sh
kubectl -n fivezerothree-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n fivezerothree-demo get pods
```

You should see something like:

```text
503
NAME                                       READY   STATUS    RESTARTS   AGE
notification-service-v1-54dd46d4b6-nz8f7   2/2     Running   0          10s
tester-69699fd775-4fwhz                    2/2     Running   0          10s
```

The request fails with `503`, and the destination is `2/2 Running` with no restarts. That rules out the obvious causes: the application is up, it has a sidecar proxy, and nothing has crashed and restarted. Whatever refused this request did it somewhere between the two pods, or before the request left the first one. The `2/2` matters here. A `1/1` pod would mean the destination has no sidecar proxy at all, so it could not take part in mesh routing, and that is a different investigation.

## Where a 503 can come from

Four different components can produce the same three digits:

```mermaid
flowchart LR
    A["tester app"] --> B["tester sidecar"]
    B -->|"network"| C["destination sidecar"]
    C --> D["destination app"]
```

The diagram shows the path of one request; the `tester` sidecar, the destination sidecar and the destination application can each answer `503`.

The `tester` sidecar answers `503` when it has no cluster, no endpoints, or no way to reach the destination. The destination sidecar answers `503` when its connection to the application fails. The destination application can also return `503` itself. You cannot tell these apart from the status code, because it carries no origin. Envoy solves this with an **access log**: one line for every request it handles. In that line it writes a short code, the **response flag**, that says why the request ended the way it did. The `demo` profile used by this playground turns access logging on. In other installs it is often off, and you must turn it on before you can read it.

## The flags in the 503 family

These are the response flags you meet with a `503`:

| Flag | Meaning | Where to look next |
| --- | --- | --- |
| `NC` | upstream cluster not found: the route named a cluster that does not exist | `DestinationRule` subsets, host names |
| `UH` | no healthy upstream host: the cluster exists and has no usable endpoints | Service selector, pod readiness, subset labels, removed endpoints |
| `NR` | no route configured: nothing matched the request | `Host` header, port protocol, `VirtualService` binding |
| `UF` | upstream connection failure: the connection could not be set up | mTLS mismatch, wrong port, network policy |
| `UC` | upstream connection termination: the connection was closed during the request | application crash, protocol mismatch |
| `-` | no flag: no proxy-level error | the **application** produced the status |

Two reading aids turn this list into a model. The `U` prefix means **upstream**, the destination side of the connection. And the flags are roughly ordered by how far the request got: `NC` never found a destination, `UH` found one with nothing in it, `UF` tried to connect and failed, `UC` connected and lost the connection. The last row saves the most time. A `503` with the flag `-` is your service's own answer, passed on unchanged. No amount of Istio debugging will explain it; the investigation belongs in the application's logs.

## Reading the line

The client proxy's access log is that proxy's own record of the request. Read the last lines of the `tester` pod's proxy log:

```sh
kubectl -n fivezerothree-demo logs deploy/tester -c istio-proxy --tail=5
```

You should see something like:

```text
2026-10-09T22:23:47.850294Z	info	cache	returned workload trust anchor from cache	ttl=23h59m59.149709307s
2026-10-09T22:23:47.850441Z	info	cache	returned workload trust anchor from cache	ttl=23h59m59.149558848s
2026-10-09T22:23:48.025271Z	info	Readiness succeeded in 280.949789ms
2026-10-09T22:23:48.025490Z	info	Envoy proxy is ready
[2026-10-09T22:23:56.668Z] "POST /notify HTTP/1.1" 503 NC cluster_not_found - "-" 0 0 0 - "-" "curl/8.22.0" "45585c55-a0d3-9fee-9965-0f467034a873" "notification-service" "-" - - 10.96.187.226:80 10.244.0.9:56710 - -
```

The first four lines are the proxy's own start-up messages. The last line, in square brackets, is the access log line for your request.

Read it from left to right and stop at the field after the status code:

```text
  "POST /notify HTTP/1.1"   503      NC       cluster_not_found      ...   "-"
   the request              status   FLAG     response code details        upstream host
```

`NC` says the proxy produced this `503`, and names the reason: the route named a cluster that the proxy does not have. Two more fields on the line carry weight. The **response code details** (`cluster_not_found` here) are Envoy's explanation in words, and for some failures, such as authorization, they are the whole answer. The **upstream host** field is `-`, which means no connection was ever attempted. On a successful request it holds an address such as `10.244.0.8:8084`, which proves the proxy connected to a pod.

## The log that stays empty

The other half of the evidence is easy to forget: check the **destination's** proxy log for the same request. Read the last lines of the `notification-service-v1` proxy log:

```sh
kubectl -n fivezerothree-demo logs deploy/notification-service-v1 -c istio-proxy --tail=5
```

No line for this request appears. That absence is evidence, and it settles the question:

| Client log | Destination log | Means |
| --- | --- | --- |
| failure | **nothing** | the request never arrived: routing, clusters, endpoints, or the connection itself |
| failure | failure | it arrived and failed there: inbound policy, or the application |
| success | failure | rare; a problem on the way back |

Here the client failed and the destination saw nothing, so the whole investigation stays on the **sending** side.

## What the flag has already told you

Before you run a single `proxy-config` command, the log has narrowed the problem to one stage of the proxy's chain:

```text
   NR  → stage 2, route        nothing matched
   NC  → stage 3, cluster      the named cluster does not exist
   UH  → stage 4, endpoint     the cluster is empty
   UF  → beyond stage 4        the connection failed at the far end
   -   → not Istio             the application answered
```

That is why "read the flag first" is a rule and not a preference. Walking the chain from the first stage with no flag takes four commands; with a flag it takes one.

> [!TIP]
> Make reading the client proxy's last log line your first step on any failing request. It tells you who answered and which stage to check, before you open a single YAML file.

You now know who answered: the `tester` sidecar proxy, with the flag `NC`, and the request never reached the destination. The flag points at the cluster stage. What it does not tell you is which object made the route name a cluster that does not exist, and that is the next step.

## Common pitfalls

> [!WARNING]
> - **Reading the application log first.** For this kind of failure the request never reaches the application, so its log is empty and proves nothing.
> - **Ignoring the response flag.** `NC`, `UH`, `UF` and `UC` point at four different layers, and `-` points out of Istio entirely.
> - **Skipping the destination's log.** The missing line there is half the diagnosis.
> - **Assuming a `503` with a healthy pod means the application is down.** `2/2 Running` plus `503` is the signature of a routing fault, not an application fault.
> - **Expecting access logs to be on.** The `demo` profile turns them on; many other installs do not.
