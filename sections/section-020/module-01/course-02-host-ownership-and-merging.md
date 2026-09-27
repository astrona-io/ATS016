# Part 2 — One Host, Two Owners

> Prerequisite: [Part 1 — How A VirtualService Becomes A Route Table](./course-01-virtualservice-to-route-table.md). Next: [Part 3 — The Route Table Is The Ground Truth](./course-03-reading-the-route-table.md).

Part 1 established that a `VirtualService` compiles into one ordered array of routes inside one virtual host. This part asks the question that follows: what happens when **two** objects want to fill the same array? The answer is not "the newer wins" and not "Istio rejects one". It is worse than either, and understanding why is what stops you writing it.

## Fixing the order would not be enough

Before going further, establish that the namespace has a second problem. One command does it, and it is worth making reflexive.

> [!TIP]
> **Try it — finding a host with two claimants**
>
> ```sh
> kubectl -n conflict-demo get virtualservice \
>   -o custom-columns='NAME:.metadata.name,HOSTS:.spec.hosts,GATEWAYS:.spec.gateways'
> ```
>
> Expect something like:
>
> ```text
> NAME                  HOSTS                      GATEWAYS
> notification          [notification-service]     <none>
> notification-extra    [notification-service]     <none>
> ```
>
> Two objects, one host, neither bound to a gateway — so both apply to mesh-internal traffic and both describe the same virtual host. Run this in any namespace where routing behaves inconsistently, before reading a line of either object. The `GATEWAYS` column is there for a reason that the end of this part explains.

## What Istio does with two claimants

Istio does not reject either object, and it does not pick a winner. It **merges** them into the single virtual host that Part 1's structure allows, concatenating their route lists.

```text
   VirtualService "notification"          VirtualService "notification-extra"
        http: [A, B]                            http: [C]
              │                                      │
              └──────────────┬───────────────────────┘
                             ▼
                   VirtualHost "notification-service..."
                        routes: [ ?, ?, ? ]     ← A, B and C, in SOME order
```

The routes all arrive. What you do not control is the order — and by Part 1's mechanism, order is the entire semantics. A configuration whose meaning depends on an ordering nobody specified is not "slightly risky"; it is a configuration whose behaviour is not defined by its inputs.

The practical consequences are what make this worth a section of its own:

- **It works.** Traffic flows, requests get answered, nothing errors. There is no outage to investigate.
- **It is stable until it is not.** The order holds until one of the objects is edited, recreated, or resynced — and then it may not.
- **The change that breaks it need not touch the object that breaks.** Someone edits `notification-extra` and `notification`'s behaviour changes. That is a debugging experience with no causal trail.
- **It survives every test you would think to run.** A test suite written after the merge settled encodes the current order as expected behaviour.

Istio's own documentation describes the outcome for conflicting hosts as undefined, and the practical rule that falls out is absolute: **exactly one `VirtualService` per host, per gateway scope.**

## What the analyzer says, and how loudly

This is one of the cases where [module 010-01's](../../section-010/module-01/course-02-reading-analyzer-messages.md) severity lesson has teeth.

> [!TIP]
> **Try it — what the analyzer makes of it**
>
> ```sh
> istioctl analyze -n conflict-demo
> ```
>
> Expect something like:
>
> ```text
> Warning [IST0109] (VirtualService notification-extra.conflict-demo) The VirtualServices notification-extra.conflict-demo, notification.conflict-demo associated with mesh gateway define the same host notification-service which can lead to undefined behavior. This can be fixed by merging the conflicting VirtualServices into a single resource.
> ```
>
> A `Warning`, not an `Error` — nothing here is invalid and Istio will serve this configuration indefinitely. Two phrases in the message are precise rather than decorative: **`associated with mesh gateway`** identifies the scope in which the conflict exists, and **`undefined behavior`** is a statement about determinism, not a hedge. The suggested fix — merge into a single resource — is the only correct one.

Note also what the message implies about detection: the analyzer found this by comparing two objects, which is exactly the cross-object class that [module 010-01 Part 1](../../section-010/module-01/course-01-admission-and-the-analysis-gap.md) showed admission control cannot reach. Both objects passed every admission stage individually.

## Scope: gateways are what make two objects legitimate

The phrase `associated with mesh gateway` points at the real ownership rule. A `VirtualService` applies within a **gateway scope**, set by `spec.gateways`:

| `spec.gateways` | Scope |
| --- | --- |
| omitted | `mesh` — the implicit default; applies to sidecars inside the mesh |
| `["mesh"]` | the same, written explicitly |
| `["my-gateway"]` | only traffic arriving through that `Gateway` |
| `["mesh", "my-gateway"]` | both |

Two objects claiming one host **in different scopes are not in conflict** — they describe different virtual hosts, in different proxies' route configurations. That is the intended design for the common case where external traffic needs different routing from internal traffic:

```text
   notification-external   gateways: [public-gw]   ──▶ ingress gateway's route table
   notification-internal   gateways: [mesh]        ──▶ every sidecar's route table
```

So "one object per host" is shorthand. The exact rule is **one object per host per scope**, and splitting by gateway binding is the legitimate way to have two — with the caveat that a `VirtualService` listing both `mesh` and a gateway reintroduces the overlap it was meant to avoid.

## The merge does have documented rules — do not rely on them

Istio does define merge behaviour in specific situations: for gateway-bound services, a `VirtualService` without a root-path rule can be merged with others, and delegation via `spec.http[].delegate` is an explicit, ordered composition mechanism.

Delegation is the supported answer when you genuinely need several teams to own parts of one host's routing: a root `VirtualService` owns the host and delegates path prefixes to other objects by name. The composition is then written down rather than inferred.

What you should not do is rely on the *incidental* merge of two independent objects that happen to name the same host. The difference between those two is the difference between a declared composition and a collision.

> [!WARNING]
> **Pitfalls in host ownership**
>
> - **Splitting one host across two `VirtualService` objects in the same scope.** Istio merges them and the resulting order is not yours to control. Consolidate, or separate them by gateway binding.
> - **Ignoring `IST0109` because it is only a Warning.** Valid configuration with undefined behaviour is the worst combination — it will pass every test you write.
> - **Assuming the newer object wins.** Nothing in Istio defines that. Neither does creation timestamp, name ordering, or file order in your repository.
> - **Believing a conflict is resolved because the symptom moved.** Editing either object can reshuffle the merge. A symptom that moves without a deliberate fix is still undefined behaviour.
> - **Listing both `mesh` and a gateway in `spec.gateways` on two objects.** The scopes now overlap again, and you are back where you started.
> - **Reaching for delegation to paper over a collision.** Delegation is for deliberate composition. If two teams are colliding, decide who owns the host first.

> *One host, one VirtualService, per gateway scope — anything else hands the ordering to something you do not control.*

## Reference

- [Virtual service reference](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — `spec.gateways`, the `mesh` reserved name, and the `delegate` field.
- [IST0109 — conflicting mesh gateway virtual service hosts](https://istio.io/latest/docs/reference/config/analysis/ist0109/) — the analyzer's own page for this finding.
- [Traffic routing: virtual services](https://istio.io/latest/docs/concepts/traffic-management/#virtual-services) — where the host-ownership model is stated conceptually.
- [Gateway reference](https://istio.io/latest/docs/reference/config/networking/gateway/) — what a gateway binding actually selects, if the scoping table above is new to you.
