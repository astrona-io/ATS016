# Part 1 — What describe Resolves For One Workload

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — Making A Proxy Narrate One Decision](./course-02-envoy-log-scopes-at-runtime.md).

`istioctl x describe pod` prints a page of facts about one workload. The page is only useful if you know what question each line answers — and, more importantly, what computation produced it. Several of those lines are the result of merging policies that live in different objects at different scopes, and that merge is the thing this part is really about.

## The problem: four objects, one pod

Four Istio objects exist in `describe-demo`. Listing them tells you nothing about which reach the workload.

> [!TIP]
> **Try it — the view that does not answer the question**
>
> ```sh
> kubectl -n describe-demo get virtualservice,destinationrule,peerauthentication,authorizationpolicy
> ```
>
> Expect something like:
>
> ```text
> NAME                                              GATEWAYS   HOSTS                      AGE
> virtualservice.networking.istio.io/notification              ["notification-service"]   5m
>
> NAME                                               HOST                   AGE
> destinationrule.networking.istio.io/notification   notification-service   5m
>
> NAME                                          MODE     AGE
> peerauthentication.security.istio.io/default  STRICT   5m
>
> NAME                                                            AGE
> authorizationpolicy.security.istio.io/notification-post-only    5m
> ```
>
> Four objects and no indication of which pod they land on, in what combination, or what the combination permits. Every one of them selects its targets by a different mechanism, which is why no `kubectl` view can join them up.

## Three different ways an object finds its target

This is the mechanism `describe` exists to hide, and knowing it is what lets you predict the output instead of reading it hopefully.

| Object | Finds its target by | Applies to |
| --- | --- | --- |
| `VirtualService` | `spec.hosts` — a hostname | the **client** proxy sending to that host |
| `DestinationRule` | `spec.host` — a hostname | the **client** proxy, on the way to that host |
| `PeerAuthentication` | `spec.selector` — pod labels, plus its namespace | the **server** proxy receiving connections |
| `AuthorizationPolicy` | `spec.selector` — pod labels, plus its namespace | the **server** proxy receiving requests |

Two consequences follow immediately. First, the networking pair is addressed by *host* and the security pair by *labels* — so a `VirtualService` can affect a workload that no `AuthorizationPolicy` selects, and vice versa. Second, the two families are enforced on **opposite ends of the connection**, which is why [section 040](../../section-040/module-01/course.md) has to distinguish inbound from outbound configuration at all.

## Scope precedence, and the word "effective"

`PeerAuthentication` and `AuthorizationPolicy` can be written at three scopes, and a workload can be covered by one of each simultaneously:

```text
   mesh-wide        an object in the root namespace (istio-system), no selector
        │                 applies to every workload in the mesh
        ▼
   namespace-wide   an object in the workload's namespace, no selector
        │                 applies to every workload in that namespace
        ▼
   workload         an object with a selector matching the pod's labels
                          applies to those pods only
```

For `PeerAuthentication` the resolution rule is **narrowest wins, evaluated per port**:

- A workload-scoped policy overrides a namespace-scoped one, which overrides the mesh-wide one.
- Overriding is not merging: the winning policy's `mtls.mode` replaces the others entirely for that workload.
- `portLevelMtls` narrows further still — a workload policy can be `STRICT` overall and `DISABLE` on one port, which is how a health-check endpoint gets exempted.

`AuthorizationPolicy` resolves differently, and the difference is worth holding separately in your head because mixing them up produces confident wrong answers:

- All policies selecting the workload **apply together**; none overrides another.
- `DENY` policies are evaluated first. Any match denies.
- Then `ALLOW` policies: if any `ALLOW` policy selects the workload, the request must match at least one of their rules, or it is denied.

That last clause is the trap. An `ALLOW` policy does not merely permit what it names — **it forbids everything it does not name**, for every workload it selects. A namespace with no `AuthorizationPolicy` at all is fully open; adding one narrow `ALLOW` closes everything else in the same instant.

Both resolutions are computations over several objects. "Effective" in `describe`'s output means *the result of that computation*, which is why reading a single object's YAML is not a substitute.

## Reading the output

The sections, and the question each answers:

| Section | The question it answers |
| --- | --- |
| `Pod` | Is this pod in the mesh at all, and which sidecar revision is it running? |
| `Pod Ports` | Which ports does the container expose, and did Istio work out a protocol for each? |
| `Service` | Which Service fronts this pod, and how does its port map to the container's? |
| `Exposed on Ingress` | Is anything outside the mesh reaching this workload through a gateway? |
| `RBAC policies` | Which `AuthorizationPolicy` rules select this workload? |
| `VirtualService` | Which routing rules match traffic to it, and which route wins? |
| `DestinationRule` | Which subsets and traffic policies apply on the way in? |
| `Effective PeerAuthentication` | The mTLS mode in force after the precedence resolution above, per port |

The `x` in the command is `experimental`. It has been stable and widely used for years; the prefix is still required and is not a reason to avoid it. `istioctl experimental describe` is the long form.

> [!TIP]
> **Try it — four objects resolved into one answer**
>
> ```sh
> istioctl x describe pod $POD -n describe-demo
> ```
>
> Expect something like:
>
> ```text
> Pod: notification-service-v1-6c9f8b7d5-x2kqp
>    Pod Revision: default
>    Pod Ports: 8084 (notification-service), 15090 (istio-proxy)
> --------------------
> Service: notification-service
>    Port: http 80/HTTP targets pod port 8084
> RBAC policies: ns[describe-demo]-policy[notification-post-only]-rule[0]
> --------------------
> Effective PeerAuthentication:
>    Workload mTLS mode: STRICT
> --------------------
> VirtualService: notification
>    Route to host "notification-service" subset "v1"
> DestinationRule: notification for "notification-service"
>    Matching subsets: v1
> ```
>
> Read `Effective PeerAuthentication` as the output of the precedence rules, not as a copy of the `PeerAuthentication` object — here the two happen to agree because only one policy exists. The `RBAC policies` line names the exact rule that will judge your requests, in the `ns[...]-policy[...]-rule[N]` form Envoy uses internally; that string reappears verbatim in the proxy's logs in [Part 2](./course-02-envoy-log-scopes-at-runtime.md).

## The consequence you can send a request to

The `ALLOW`-forbids-the-rest rule is not a detail. The policy here permits `POST`, so a `GET` to the same path is refused by the sidecar before the application is ever invoked.

> [!TIP]
> **Try it — the same path, two verbs**
>
> ```sh
> kubectl -n describe-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'POST %{http_code}\n' -X POST http://notification-service/notify
> kubectl -n describe-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'GET  %{http_code}\n' -X GET http://notification-service/notify
> ```
>
> Expect something like:
>
> ```text
> POST 200
> GET  403
> ```
>
> The `403` is produced by the destination's proxy, so the application's own log is empty and its metrics show no request. `describe` told you which policy was responsible before you sent anything — and it also told you where to look next, because the policy is enforced inbound.

## The warnings at the bottom

`describe` ends with warnings, and they are the most valuable part of the output — partly because they are below the fold. Two recur constantly, and both describe configuration that is present, valid and inert.

**A Service port with no protocol.** Istio infers a port's protocol from its `name` (`http`, `http2`, `grpc`, `tcp`, `tls`, …, optionally with a suffix like `http-notify`) or from `appProtocol`. A port named `web`, or unnamed, falls back to plain TCP — and at that moment every HTTP feature stops applying to it: header routing, retries, per-route timeouts, HTTP metrics, `AuthorizationPolicy` rules written against methods or paths. The objects remain valid; they simply never match, because there is no HTTP layer for them to match on.

**A policy that cannot take effect**, usually because its selector matches no pod, or it targets a port the Service does not expose. The `ALLOW` semantics above make this specifically dangerous in the other direction too: a selector typo can turn an intended restriction into no restriction at all.

Both are findings you would otherwise reach only by noticing that something you wrote has no observable effect.

> [!WARNING]
> **Pitfalls in reading a workload's effective configuration**
>
> - **Reading only the top of `describe`.** The warnings at the end — an unnamed Service port, a policy whose selector matches nothing — are usually the answer.
> - **Expecting `describe` to find cluster-wide problems.** It is strictly a per-pod view. A `Gateway` nobody bound to, or a namespace missing its injection label, will not appear; that is `analyze`'s job.
> - **Reading one `PeerAuthentication` object and calling it the mode.** Mesh, namespace and workload policies resolve narrowest-first, per port. Only `Effective PeerAuthentication` accounts for that.
> - **Treating `AuthorizationPolicy` like `PeerAuthentication`.** They resolve by completely different rules: one overrides, the other accumulates, and a single `ALLOW` policy denies everything it does not explicitly permit.
> - **Assuming a `403` came from the application.** When a policy selects the workload, the sidecar refuses before the container sees the request.

> *"Effective" is a computation, not a field: it is what several objects at several scopes resolve to for this one pod.*

## Reference

- `istioctl experimental describe pod --help` — the flag list, including `--ignoreUnmeshed` for scripting over mixed namespaces.
- [Describing pod configuration](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-describe/) — Istio's own walkthrough, with more output examples including ingress exposure.
- [Peer authentication](https://istio.io/latest/docs/reference/config/security/peer_authentication/) — the scope precedence and `portLevelMtls` rules, stated normatively.
- [Authorization policy](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — the `DENY`-then-`ALLOW` evaluation order; worth reading once for the precise wording of the implicit deny.
- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — how a port's name becomes a protocol, and the exact list of recognised prefixes.
