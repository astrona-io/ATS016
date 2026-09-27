# Part 2 — Reading The Table

> Prerequisite: [Part 1 — How Configuration Reaches A Proxy](./course-01-xds-and-acknowledgement.md). Next: [Part 3 — Absence, And The Per-Proxy Diff](./course-03-absence-and-per-proxy-diff.md).

`istioctl proxy-status` asks `istiod` for the bookkeeping from Part 1 and prints one row per connected proxy. This part reads that table field by field: what each state eliminates, and what the two right-hand columns answer that has nothing to do with sync at all.

## The table

> [!TIP]
> **Try it — the healthy baseline**
>
> ```sh
> istioctl proxy-status
> ```
>
> Expect something like:
>
> ```text
> NAME                                              CLUSTER        CDS        LDS        EDS        RDS        ECDS       ISTIOD                     VERSION
> istio-ingressgateway-...istio-system              Kubernetes     SYNCED     SYNCED     SYNCED     NOT SENT   NOT SENT   istiod-7d4c9b8f4-k2m8x     1.30.5
> notification-service-v1-...proxysync-demo         Kubernetes     SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT   istiod-7d4c9b8f4-k2m8x     1.30.5
> tester-...proxysync-demo                          Kubernetes     SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT   istiod-7d4c9b8f4-k2m8x     1.30.5
> ```
>
> Three proxies, all attached to the same `istiod` pod, all matching the control plane version. The `NAME` column is `<pod>.<namespace>` — that exact string is what [Part 3](./course-03-absence-and-per-proxy-diff.md) passes back to the command to inspect one proxy. Column sets vary between Istio releases; the four from Part 1 are always there.
>
> Note the ingress gateway's `RDS: NOT SENT`. Nothing is wrong with it: no `Gateway` or `VirtualService` is bound to it in this cluster, so there are no HTTP routes to send. Absence of configuration is not absence of health.

## The three states

Each state eliminates a different set of theories, which is the entire value of running this early.

**`SYNCED`** — `istiod` sent this resource type and the proxy ACKed it. The proxy has your configuration. If behaviour is still wrong, **the configuration itself is wrong**, and the investigation moves to `istioctl proxy-config` to see what the proxy made of it.

What `SYNCED` does *not* prove is worth stating plainly, because the word invites over-reading: it is an acknowledgement that bytes were accepted, not a judgement that they express your intent. A proxy routing every request to the wrong subset is perfectly `SYNCED`.

**`NOT SENT`** — `istiod` has nothing to send for that type. Usually normal:

| Type `NOT SENT` | Normal when |
| --- | --- |
| `RDS` | the proxy has no HTTP routes — e.g. a gateway with nothing bound to it |
| `ECDS` | no WebAssembly or extension configuration exists in the mesh |
| `EDS` | rare; would mean no clusters need dynamic endpoints |

It is a symptom only when you expected that resource type to exist. A sidecar in an application namespace showing `RDS: NOT SENT` while the application makes HTTP calls is a real finding.

**`STALE`** — `istiod` sent an update and has not received an ACK. From [Part 1](./course-01-xds-and-acknowledgement.md), this covers two very different situations:

- the proxy has not answered yet — slow, overloaded, or the connection is degraded;
- the proxy answered with a **NACK** — it rejected the configuration and is still running the previous version.

The second is the one to rule in or out first, because it means your change will never take effect no matter how long you wait. The evidence is on the control plane side (`pilot_total_xds_rejects` and a `reject` line in the `istiod` log, per [module 030-01 Part 2](../module-01/course-02-instruments-logs-and-metrics.md)) and on the proxy side in its container log.

A brief `STALE` immediately after an apply is normal — it is the window between push and ACK. A persistent one is not.

## Transitions, not snapshots

The states are points in a small lifecycle, and knowing the transitions tells you whether what you are seeing is a moment or a condition:

```text
                  you apply a change
                          │
   SYNCED ───── push ────▶ STALE ──── ACK ────▶ SYNCED
                            │
                            └──── NACK ───▶ STALE (persistent)
                                            proxy keeps previous config

   any state ──── proxy disconnects ────▶ (row disappears entirely)
```

That last transition is why Part 3 exists: disconnection is not a state in this table, it is an absence from it.

The practical technique that follows: when checking whether a change landed, run the command **twice, a few seconds apart**. A `STALE` that becomes `SYNCED` is the protocol working. A `STALE` that stays is a fault.

## The ISTIOD column

`ISTIOD` names the control plane pod serving that proxy. Two uses.

**Canary upgrades.** When a new `istiod` revision runs alongside the old one, a workload moves between them only when its pod is recreated with the new revision label. This column is the direct evidence that the move happened. A pod you relabelled and restarted should show the new revision's pod name; if it does not, the relabelling did not take — and [module 030-03](../module-03/course.md) has the label precedence rules that explain why.

**Load distribution.** With several `istiod` replicas, each proxy attaches to exactly one. A sharply uneven distribution across replicas — which this column shows at a glance — is worth noticing, because proxies redistribute only when their stream drops.

## The VERSION column, and the skew rule

`VERSION` is the proxy's own Istio version. Compare it against the control plane's, and apply Istio's support rule:

> A data plane proxy may be **at most one minor version behind** `istiod`, and must never be ahead.

The reasoning is the ordering of an upgrade. `istiod` is upgraded first and must keep serving proxies that have not restarted yet, so it knows how to generate configuration for one older minor version. The reverse case has no such guarantee: a newer proxy can be sent configuration from an older control plane that does not know about its features.

The practical consequence of skew is quiet rather than loud. A `1.24.0` proxy against a `1.30.5` control plane keeps working — it simply never receives anything that depends on a newer feature, so a policy you wrote using a recent field applies to some workloads and not others.

> [!TIP]
> **Try it — control plane version against proxy versions**
>
> ```sh
> istioctl version
> istioctl proxy-status | awk 'NR==1 || NF>1 {print $1, $NF}'
> ```
>
> Expect something like:
>
> ```text
> client version: 1.30.5
> control plane version: 1.30.5
> data plane version: 1.30.5 (3 proxies)
> NAME                                       VERSION
> istio-ingressgateway-...istio-system       1.30.5
> notification-service-v1-...proxysync-demo  1.30.5
> tester-...proxysync-demo                   1.30.5
> ```
>
> `istioctl version` already summarises the data plane and will list several versions when skew exists — that is the faster check. The per-proxy listing is what you need afterwards, when it reports two versions and you have to find out *which* pods are behind so you can restart them.

Note the three lines `istioctl version` prints. `client version` is your local binary, and it can differ from both of the others without anything being wrong — but a client several minors from the control plane may print output that does not match what this course shows.

> [!WARNING]
> **Pitfalls in reading the table**
>
> - **Reading `SYNCED` as "correct".** It means the proxy accepted what it was sent. Wrong configuration synchronises perfectly.
> - **Treating every `NOT SENT` as a fault.** It is expected for `RDS` on a proxy with no HTTP routes and for `ECDS` in a mesh with no extensions.
> - **Reading a single `STALE` as a failure.** Run the command again a few seconds later. Transient is the protocol; persistent is the fault.
> - **Assuming `STALE` means slow.** It equally means NACKed — the proxy refused the update and is still serving the previous one. Check the `istiod` log for `reject`.
> - **Ignoring the `VERSION` column after an upgrade.** Proxies keep the old version until their pods restart, and a badly skewed proxy silently ignores newer features.
> - **Forgetting the `ISTIOD` column during a canary.** It is the only direct evidence that a relabelled workload actually moved revisions.

> *The table reports an acknowledgement, not a judgement: SYNCED tells you the proxy has your configuration, never that your configuration is right.*

## Reference

- `istioctl proxy-status --help` — the per-proxy form, output options, and the `--revision` flag for multi-revision meshes.
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — Istio's walkthrough of this command with more output examples.
- [Supported releases and version skew](https://istio.io/latest/docs/releases/supported-releases/) — the normative statement of the one-minor-version rule.
- [Canary upgrades](https://istio.io/latest/docs/setup/upgrade/canary/) — revisions, the `istio.io/rev` label, and what the `ISTIOD` column is confirming.
