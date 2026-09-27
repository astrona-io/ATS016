# Part 3 — Choosing The Fix, And The Other Cause

> Prerequisite: [Part 2 — Walking The Chain](./course-02-walking-the-chain.md). Next: [the module landing page](./course.md), then [section 050](../../section-050/module-01/course.md).

A dangling reference can always be resolved from either end: create the target, or stop referencing it. Only one of those is correct in any given case, and choosing wrong produces a configuration that satisfies the analyzer while still failing. This part makes the choice explicit, proves the fix properly, and then covers a second cause that produces the same `503` from a completely different place.

## Two fixes, one correct

The `VirtualService` names `subset: v2`. The `DestinationRule` defines only `v1`. Two edits would make the reference resolve:

**Option A — route to a subset that exists.** Change the `VirtualService` to `subset: v1`.

Correct when the `v2` reference was a mistake, which is the usual case: a manifest copied from an environment where `v2` was deployed, a version rolled back without updating routing, a subset renamed on one side only.

**Option B — define the missing subset.** Add `v2` to the `DestinationRule`.

Correct **only if pods labelled `version: v2` actually exist**. Here they do not — the namespace runs one Deployment labelled `version: v1`.

The failure mode of choosing B wrongly is specific and worth internalising, because it looks like progress:

```text
   before:   route → v2,  no v2 cluster          →  503, flag NC
                                                     "the cluster does not exist"

   add a v2 subset whose labels match no pod:

   after:    route → v2,  v2 cluster exists      →  503, flag UH
             cluster has NO endpoints                "no healthy upstream host"
```

The analyzer goes quiet — `IST0101` is satisfied, the reference resolves. The traffic still fails. And the diagnosis is now *harder*, because the loud, unambiguous "this does not exist" has been replaced by the vaguer "there is nothing behind it", which has four possible causes ([module 040-01 Part 3](../module-01/course-03-clusters-and-endpoints.md)) instead of one.

The rule that generalises: **make the reference true in the direction that matches reality.** Check what is deployed before inventing a target for it.

```sh
kubectl -n fivezerothree-demo get pods --show-labels | grep notification
```

One command, and it decides the fix.

## Applying it

> [!TIP]
> **Try it — routing to something real**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: notification
>   namespace: fivezerothree-demo
> spec:
>   hosts:
>     - notification-service
>   http:
>     - route:
>         - destination:
>             host: notification-service
>             subset: v1
> EOF
> kubectl -n fivezerothree-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
> ```
>
> Expect something like:
>
> ```text
> virtualservice.networking.istio.io/notification configured
> 200
> ```
>
> The fix took effect within a second or two and no pod restarted. A `VirtualService` edit becomes an RDS push over the existing xDS stream ([module 030-02 Part 1](../../section-030/module-02/course-01-xds-and-acknowledgement.md)), and the proxy swaps its route table in place. If a routing change ever *does* seem to need a restart, that is a delivery problem and `istioctl proxy-status` is the next command — not `kubectl rollout restart`.

## Proving it from three directions

A `200` is good evidence and not complete evidence. Three sources were wrong at the start of this module, and all three should now agree:

| Source | Proves |
| --- | --- |
| a real request | the behaviour is right **now** |
| the proxy's route table | the proxy holds what you think it holds |
| `istioctl analyze` | the configuration set is coherent |

Each can be right while another is wrong. A `200` with analyzer errors means you are getting lucky on a path that does not touch the broken object. A clean analyze with a `503` means the configuration is coherent and has not reached the proxy.

> [!TIP]
> **Try it — the chain, now intact**
>
> ```sh
> istioctl proxy-config routes deploy/tester -n fivezerothree-demo -o json \
>   | grep '"cluster"' | grep notification
> istioctl analyze -n fivezerothree-demo
> kubectl -n fivezerothree-demo logs deploy/tester -c istio-proxy --tail=1
> ```
>
> Expect something like:
>
> ```text
>         "cluster": "outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local",
> ✔ No validation issues found when analyzing namespace: fivezerothree-demo.
> [...] "POST /notify HTTP/1.1" 200 - via_upstream - ... "10.244.0.12:8084" outbound|80|v1|notification-service... 
> ```
>
> Three confirmations. The access log line is the one that closes the loop most precisely: flag `-` where it was `NC`, and an **upstream host address** where there was a `-`. That address is the proof that a connection actually happened, and it is the same field Part 1 used to show that one never had.

## The other cause of the same 503

A missing subset is not the only way to get a `503` out of a healthy service. The other frequent cause is a **Service port whose name does not declare a protocol** — and it is worth knowing because nothing about the symptom points at a Service definition.

Istio decides how to treat traffic on a port from the port's `name` (`http`, `http2`, `grpc`, `tcp`, `tls`, `mongo`, …, optionally suffixed as `http-notify`) or from the `appProtocol` field. A port named `web`, or unnamed, gets no declared protocol, and Istio falls back to sniffing the first bytes — which works for plain HTTP and fails for anything else ([module 040-01 Part 1](../module-01/course-01-capture-and-listeners.md)).

When the port is treated as plain TCP, the consequences cascade:

```text
   port has no declared protocol
        │
        ├── no HTTP route is built for it       → VirtualService rules never apply
        ├── no HTTP filters are installed       → retries, timeouts, header routing gone
        ├── no HTTP telemetry                   → the service vanishes from dashboards
        └── depending on configuration          → 503, or worse: a 200 that ignored every rule
```

The last outcome is the nastiest. Traffic succeeds, so nobody investigates, and every routing rule written for that service is silently inert.

The tells, in order of speed:

1. **`istioctl x describe pod`** reports it as a warning ([module 010-02 Part 1](../../section-010/module-02/course-01-what-describe-resolves.md)) — the fastest check.
2. **`istioctl proxy-config listener`** shows the difference directly: an HTTP-aware port has `Trans: raw_buffer; App: http/1.1,h2c` and hands off to a named `Route:`, while a TCP-treated port has a direct `Cluster:` destination and no route at all.
3. **The route table** simply has no virtual host for that service on that port.

The fix is a one-word edit to the Service, and it requires no restart of anything:

```sh
kubectl -n <ns> patch svc <name> --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/name","value":"http"}]'
```

## The method, generalised

Everything in this module reduces to five steps that apply to any `503`:

```text
   1. Read the response flag on the CLIENT proxy.          who failed it, and at which layer
   2. Check the DESTINATION proxy's log.                   did it arrive at all
   3. Run istioctl analyze.                                is there a named configuration fault
   4. Walk route → cluster → endpoint if not.              find the missing link
   5. Fix the end that matches reality, verify three ways. behaviour, configuration, coherence
```

Steps 1 and 2 cost one command each and eliminate most of the search space. Step 5's discipline — one change, then re-verify — is what makes the fix defensible rather than coincidental.

> [!WARNING]
> **Pitfalls in fixing**
>
> - **Adding the missing subset reflexively.** A subset whose labels match no pod converts an `NC` into a `UH`: the analyzer goes quiet, the traffic still fails, and the diagnosis gets harder.
> - **Fixing several things in one apply.** When the symptom clears you will not know which change mattered, and an unverifiable fix is not a fix.
> - **Stopping at a `200`.** Confirm the proxy's route table and the analyzer too; either can disagree with a lucky request.
> - **Restarting pods after a routing change.** Routing is pushed over xDS. If it has not landed, the problem is delivery, not the pod.
> - **Forgetting the port name.** An unnamed or undeclared Service port silently disables every HTTP routing rule aimed at it, and the symptoms look nothing like a naming problem.
> - **Assuming the fix belongs in Istio.** A `503` with flag `-` came from your application. Nothing in this module applies to it.

> *Resolve a dangling reference in the direction reality points — inventing the target just trades a clear failure for a murky one.*

## Reference

- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — the port-naming rules and the exact list of recognised names.
- [Common problems — 503 errors](https://istio.io/latest/docs/ops/common-problems/network-issues/) — the other `503` variants, including the ones this module does not cover.
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — subsets and label selectors, for deciding whether Option B is ever right.
- [Envoy access logging](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage) — the upstream-host field used as proof above.
