# Part 2 — Labels, Selectors And Precedence

> Prerequisite: [Part 1 — How Injection Actually Happens](./course-01-the-injection-webhook.md). Next: [Part 3 — Working The Checklist](./course-03-working-the-checklist.md).

Part 1 showed two selectors gating the webhook call and one decision being made. This part is the decision: which labels participate, where they live, and what happens when several of them disagree. Getting the precedence right is the difference between fixing an injection problem in one command and changing labels hopefully until something works.

## Two namespace labels, not one

A namespace opts into injection with one of two labels, and they are not interchangeable:

| Label | Means | Used when |
| --- | --- | --- |
| `istio-injection=enabled` | inject using the **default** control plane revision | a single, unversioned Istio install |
| `istio.io/rev=<revision>` | inject using the named **revision** | several `istiod` revisions run side by side — canary upgrades, or multiple control planes |

Neither present means no injection for anything in that namespace.

The revision label is not an alternative spelling. It names *which control plane* will serve the workloads, and that choice propagates: the injected proxy is configured by that revision, connects to that revision's `istiod`, and appears against that pod name in the `ISTIOD` column of [`proxy-status`](../module-02/course.md).

> [!TIP]
> **Try it — what the namespace asks for**
>
> ```sh
> kubectl get ns noinject-demo --show-labels
> ```
>
> Expect something like:
>
> ```text
> NAME            STATUS   AGE   LABELS
> noinject-demo   Active   11m   istio-injection=enabled,kubernetes.io/metadata.name=noinject-demo
> ```
>
> The namespace is labelled correctly, so this is not the cause here — and eliminating the most common explanation in one command is worth as much as finding a fault would be. Note what is absent: no `istio.io/rev`, so the default control plane serves this namespace.

## What the webhook itself selects on

The labels above are only meaningful because the `MutatingWebhookConfiguration` selects on them. Reading that object turns the convention into a rule you can verify.

```sh
kubectl get mutatingwebhookconfiguration istio-sidecar-injector \
  -o jsonpath='{range .webhooks[*]}{.name}{"\n  ns: "}{.namespaceSelector}{"\n  obj: "}{.objectSelector}{"\n"}{end}'
```

A typical default install defines several webhook entries, and between them they implement this logic:

```text
   namespaceSelector decides: should istiod even be asked about pods in this namespace?
        matches istio-injection=enabled            → yes (default revision)
        matches istio.io/rev in (<this revision>)  → yes (that revision)
        neither                                    → the webhook is never called

   objectSelector decides: should istiod be asked about THIS pod?
        excludes pods labelled sidecar.istio.io/inject=false
```

Two things follow that are not obvious from the documentation-level description:

- **A namespace that matches no webhook entry is not "injection disabled" — it is invisible to the injector.** The API server never calls `istiod` at all, so nothing is logged anywhere. There is no error to find because no conversation happened.
- **The exclusion for `sidecar.istio.io/inject=false` is implemented as a selector**, which is why it is absolute: the webhook is not called, so no namespace setting can override it.

The exact expressions differ by Istio version and install profile. What you are checking, when you read this object, is that **some branch of it matches the labels your namespace actually has**.

## The pod-template opt-out

A pod can decline injection even in an enabled namespace, with the label `sidecar.istio.io/inject: "false"`. Its location is the part people get wrong:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reporting-service
  labels:
    app: reporting-service              # ← the Deployment's own labels: IRRELEVANT here
spec:
  template:
    metadata:
      labels:
        app: reporting-service
        sidecar.istio.io/inject: "false"   # ← the POD TEMPLATE: this is the one that counts
```

The webhook sees pods. A label on the Deployment's `metadata` is never copied to the pods it creates, so putting the opt-out there has no effect whatsoever — and putting it there *believing* it works is a way to think a workload is excluded when it is not.

The setting exists for good reasons: jobs that must not wait for a proxy to be ready, workloads that manage their own networking, pods that talk only to things outside the mesh. It also travels: it is inherited by every manifest copied from that one, long after the original reason has gone.

> [!TIP]
> **Try it — what the pod template asks for**
>
> ```sh
> kubectl -n noinject-demo get deploy reporting-service \
>   -o jsonpath='{.spec.template.metadata.labels}{"\n"}'
> kubectl -n noinject-demo get deploy notification-service-v1 \
>   -o jsonpath='{.spec.template.metadata.labels}{"\n"}'
> ```
>
> Expect something like:
>
> ```text
> {"app":"reporting-service","sidecar.istio.io/inject":"false"}
> {"app":"notification-service","version":"v1"}
> ```
>
> There is the cause. Comparing the broken workload against a working one in the same command is a habit worth keeping: a label you are not expecting is far easier to notice next to one you are. Note the JSONPath targets `.spec.template.metadata.labels` — the pod template — not `.metadata.labels`.

## Precedence, stated once

Several settings can apply to one pod. The resolution, in order:

```text
   1. Pod template label  sidecar.istio.io/inject: "false"
           → NOT injected. Beats everything below. (objectSelector excludes the pod)

   2. Pod template label  sidecar.istio.io/inject: "true"
           → can opt a pod IN where the namespace default is off,
             but only if the namespace is in scope for the webhook at all

   3. Namespace label  istio-injection=enabled
           → injected by the DEFAULT revision.
             If istio.io/rev is ALSO present, this one wins and the revision label is ignored.

   4. Namespace label  istio.io/rev=<revision>
           → injected by that revision

   5. Nothing
           → not injected
```

Rule 3 is the trap, and it is specifically an upgrade trap. During a canary you relabel a namespace `istio.io/rev=1-26-0` and expect it to move. If the old `istio-injection=enabled` label was left in place, the namespace stays on the default revision — while looking, to anyone reading the labels, as though it is pinned to the new one. The symptom is a workload that never moves no matter how many times you restart it, and the confirmation is the `ISTIOD` column in `proxy-status` still naming the old pod.

Remove the old label when you add the revision label. That is the whole fix, and it is one command.

## Injection during a control plane outage

One more input to the decision, which is not a label at all: whether `istiod` answered. From [module 030-01](../module-01/course-03-outage-anatomy-and-rejects.md), the webhook's `failurePolicy` decides what the API server does when the call fails:

| `failurePolicy` | Result | How it looks |
| --- | --- | --- |
| `Fail` (Istio default) | pod creation is rejected | loud — `FailedCreate` events, rollouts stuck |
| `Ignore` | pod is created **without** a sidecar | silent — rollout succeeds, workload outside the mesh |

`Ignore` produces exactly the state this module is about, with every label correct. If you are investigating a namespace where *some* pods have sidecars and some do not, and the labels are uniform, look at when the sidecar-less pods were created and check whether the control plane was healthy at that time.

> [!WARNING]
> **Pitfalls with labels and precedence**
>
> - **Putting `sidecar.istio.io/inject` on the Deployment's own `metadata.labels`.** It must be on `spec.template.metadata.labels` to reach a pod. Anywhere else it does nothing.
> - **Setting both namespace labels.** `istio-injection=enabled` overrides `istio.io/rev`, so a namespace you believe is pinned to a canary revision is quietly served by the default one.
> - **Expecting a namespace label to override a pod opt-out.** It cannot — the opt-out is enforced by the webhook's `objectSelector`, so `istiod` is never consulted.
> - **Assuming "no injection" leaves a trace.** A namespace matching no webhook selector produces no call and no log line anywhere.
> - **Reading the injection labels without reading the webhook.** The selectors are the actual rule; the labels only matter because the selectors name them.

> *The pod-template opt-out beats every namespace setting, and `istio-injection=enabled` beats `istio.io/rev` — in that order, every time.*

## Reference

- [Controlling the injection policy](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/#controlling-the-injection-policy) — the label table and the override semantics, stated normatively.
- [Canary upgrades — revision labels](https://istio.io/latest/docs/setup/upgrade/canary/#data-plane) — the `istio.io/rev` workflow, including removing the old label.
- [Labels and selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) — `matchExpressions` semantics, if the webhook selector above was hard to read.
- `kubectl get mutatingwebhookconfiguration -o yaml` — the selectors your own cluster actually applies; the final authority over any documentation.
