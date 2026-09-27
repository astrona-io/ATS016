# Part 1 — How A VirtualService Becomes A Route Table

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — One Host, Two Owners](./course-02-host-ownership-and-merging.md).

A `VirtualService` is not executed. It is **translated** — into a data structure Envoy evaluates per request, with fixed semantics that your YAML inherits whether you know them or not. This part follows that translation, then uses it to explain why a rule you wrote correctly can never run.

## The symptom to keep in mind

The intent behind this namespace is easy to state: a request carrying the header `testing: true` should reach `v2`; everything else should reach `v1`. Someone wrote exactly that, and it does not happen.

> [!TIP]
> **Try it — the route that was written and does not fire**
>
> ```sh
> kubectl -n conflict-demo exec deploy/tester -- sh -c \
>   'curl -s -X POST -H "testing: true" http://notification-service/notify; echo'
> kubectl -n conflict-demo exec deploy/tester -- sh -c \
>   'curl -s -X POST http://notification-service/notify; echo'
> ```
>
> Expect something like:
>
> ```text
> ["EMAIL"]
> ["EMAIL"]
> ```
>
> Both requests reached `v1`. The header made no difference at all — and that totality is itself a clue. A rule that *partly* works points at a matching bug: a wrong header name, a `prefix` where you wanted `exact`. A rule with no effect whatsoever points at a rule that was never consulted.

## The translation

Istio converts your object into Envoy's routing structures, which are nested three deep:

```text
   VirtualService (your object)
        │  hosts: [notification-service]
        │  http:  [rule, rule, ...]
        ▼
   RouteConfiguration            ← named after the port: "80"
        │
        ├── VirtualHost          ← one per destination host
        │     domains: [notification-service,
        │               notification-service.conflict-demo,
        │               notification-service.conflict-demo.svc.cluster.local,
        │               10.96.44.31]        ← the Service's ClusterIP, too
        │     routes: [ ... ]    ← YOUR http RULES, IN ORDER
        │
        └── VirtualHost (other services this proxy knows about)
```

Three things in that diagram matter later:

- **The route configuration is named after the port**, not the service. That is why `--name 80` is how you ask a proxy for it in [Part 3](./course-03-reading-the-route-table.md).
- **The virtual host is selected by the request's `Host` header**, matched against `domains`. Not by the IP you connected to — by the header. That is why overriding `Host` can make a request miss every route.
- **`routes` is an ordered array**, and its order is your `http:` list's order. Nothing re-sorts it by specificity.

## Per-request evaluation

For each request the proxy walks the selected virtual host's `routes` from index 0:

```text
   request ──▶ route[0].match?  ── yes ──▶ take route[0].route, STOP
                     │ no
                     ▼
               route[1].match?  ── yes ──▶ take route[1].route, STOP
                     │ no
                     ▼
                    ...
                     │ no
                     ▼
               no route matched  ──▶  404, response flag NR
```

**First match wins, evaluation stops.** There is no "best match", no specificity scoring, no continuation. A routing table is an `if` / `else if` chain, not a set of rules considered together.

The second half of the mechanism is what makes it bite: a rule with **no `match` block** compiles to a route with a prefix match on `/`, which is true for every HTTP request. It is not a fallback and it is not marked as a default — it is simply a condition that always holds.

```text
http:
  - route: → v1              ← no match: compiles to prefix "/" — always true
  - match: headers.testing   ← index 1, never reached
    route: → v2
```

Everything below an unconditional rule is unreachable. Envoy does not warn, `istioctl analyze` does not flag it as an error, and the object remains perfectly valid. In a programming language your compiler would call this dead code; here it is a silently accepted configuration.

> [!TIP]
> **Try it — reading the order the author wrote**
>
> ```sh
> kubectl -n conflict-demo get virtualservice notification -o yaml | sed -n '/^spec:/,$p'
> ```
>
> Expect something like:
>
> ```text
> spec:
>   hosts:
>   - notification-service
>   http:
>   - route:
>     - destination:
>         host: notification-service
>         subset: v1
>   - match:
>     - headers:
>         testing:
>           exact: "true"
>     route:
>     - destination:
>         host: notification-service
>         subset: v2
> ```
>
> The catch-all is at index 0 and the header rule at index 1. Both rules are individually correct — that is precisely why this survives review. The defect is not in either rule; it is in their relative position, which is a property of the list rather than of anything you could point at in isolation.

## Match semantics, briefly

Understanding what counts as "a match" prevents the neighbouring mistake, where a rule is reachable and still never fires.

Within one `match` entry, **all** conditions must hold — `uri` *and* `headers` *and* `method` are ANDed. Between entries in the `match` **list**, any one entry matching is enough — they are ORed:

```yaml
- match:
    - uri: { prefix: /api }      # entry 1:  (uri prefix /api)
      headers:
        testing: { exact: "true" }  #          AND header testing=true
    - uri: { prefix: /admin }    # entry 2:  OR (uri prefix /admin)
  route: ...
```

String conditions come in three forms — `exact`, `prefix`, `regex` — and header **values** are matched with them while header **names** are matched literally and case-insensitively. A common near-miss is writing `exact: true` (a YAML boolean) where the header value is the string `"true"`; quoting it is not optional.

## The rule that follows

Order your rules **most specific first, unconditional last**. That single sentence is the whole of this part applied, and it is the same discipline as writing an `if` / `else if` / `else` chain — which fails in exactly the same way when the `else` is moved to the top.

If you find yourself wanting two unconditional rules, you have written one rule and one piece of dead configuration.

> [!WARNING]
> **Pitfalls in a single VirtualService**
>
> - **Putting the default route first.** A rule with no `match` is unconditional, not a fallback. Everything below it is unreachable, and nothing reports it.
> - **Expecting specificity to win.** Envoy does not rank routes. Index order decides, full stop.
> - **Writing `exact: true` unquoted.** That is a boolean, not the string `"true"`, and the header will not match.
> - **Assuming routing follows the address you dialled.** The virtual host is chosen by the `Host` header against `domains`; a rewritten or overridden `Host` lands you somewhere else, or nowhere.
> - **Reading a partial failure and a total failure the same way.** Partial means the match is wrong; total usually means the rule is never reached.

> *A VirtualService compiles to an ordered array, and an unconditional rule is not a default — it is a wall.*

## Reference

- [Virtual service reference](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — `HTTPMatchRequest` in particular, for the exact AND/OR semantics and every string match form.
- [Envoy route configuration](https://www.envoyproxy.io/docs/envoy/latest/api-v3/config/route/v3/route.proto) — the `RouteConfiguration` / `VirtualHost` / `Route` structure your object is translated into.
- [Route matching](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/http/http_routing#route-matching) — Envoy's own statement of first-match-wins, from the side that implements it.
