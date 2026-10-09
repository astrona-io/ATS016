# Labels, Selectors And Precedence

Astronaut, the injection webhook (the launch-pad crew) decides at launch whether a ship gets a communications officer. This part is that decision: which labels take part, where they live, and what happens when several of them disagree. Getting the order right is the difference between fixing an injection problem with one command and changing labels hopefully until something works.

## Two namespace labels, not one

A planet (namespace) asks for injection with one of two labels, and they are not the same thing:

| Label | Means | Used when |
| --- | --- | --- |
| `istio-injection=enabled` | Inject using the **default** control plane revision | A single Istio install with no named versions |
| `istio.io/rev=<revision>` | Inject using the named **revision** | Several `istiod` revisions run side by side, for example during a canary upgrade |

If neither label is present, nothing in that namespace is injected.

A revision is a named shift at mission control: one `istiod` installation with its own name. The revision label is not another spelling of the first label. It names *which control plane* serves the workloads. The injected proxy is configured by that revision, connects to that revision's `istiod`, and shows that `istiod` pod in the `ISTIOD` column of `istioctl proxy-status`.

<!-- astrona:playground:renew -->

### See what the namespace asks for

Show the labels on the playground's namespace:

```sh
kubectl get ns noinject-demo --show-labels
```

You should see something like:

```text
NAME            STATUS   AGE   LABELS
noinject-demo   Active   11m   istio-injection=enabled,kubernetes.io/metadata.name=noinject-demo
```

The namespace is labelled correctly, so that is not the cause here. Ruling out the most common explanation in one command is worth as much as finding a fault. Notice what is missing: there is no `istio.io/rev`, so the default control plane serves this namespace.

## What the webhook itself selects on

The labels only matter because the `MutatingWebhookConfiguration` (the object that registers the injection webhook with the API server) selects on them. Reading that object turns the convention into a rule you can check.

### Print the webhook's selectors

Print each webhook entry with its namespace selector and its object selector:

```sh
kubectl get mutatingwebhookconfiguration istio-sidecar-injector \
  -o jsonpath='{range .webhooks[*]}{.name}{"\n  ns: "}{.namespaceSelector}{"\n  obj: "}{.objectSelector}{"\n"}{end}'
```

A typical default install has several webhook entries. Between them, they work like this:

| Selector | Question it answers | Result |
| --- | --- | --- |
| `namespaceSelector` | Should `istiod` even be asked about pods on this planet? | Yes if the namespace has `istio-injection=enabled` (default revision) or `istio.io/rev` naming this revision; otherwise the webhook is never called |
| `objectSelector` | Should `istiod` be asked about **this** pod? | No for pods labelled `sidecar.istio.io/inject=false` |

Two things follow that are not obvious from the documentation:

- **A namespace that matches no webhook entry is not "injection disabled". It is invisible to the injector.** The API server never calls `istiod`, so nothing is logged anywhere. There is no error to find, because no conversation happened.
- **The `sidecar.istio.io/inject=false` exclusion is built as a selector**, which is why it is absolute. The webhook is never called, so no namespace setting can override it.

The exact expressions differ between Istio versions and install profiles. When you read this object, you are checking that **some entry matches the labels your namespace really has**.

## The pod-template opt-out

A pod can refuse injection even on a planet where injection is on, with the label `sidecar.istio.io/inject: "false"`. In space terms, these are the ship's own orders, "no officer on board", and they beat the planet's rule. Where the label sits is the part people get wrong.

### Where the label has to live

This Deployment fragment is not something to apply. It only shows the two places a label can sit:

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

The webhook sees pods. A label in the Deployment's own `metadata` is never copied to the pods it creates, so an opt-out there does nothing at all. Putting it there and *believing* it works is a way to think a workload is excluded when it is not.

The opt-out exists for good reasons: jobs that must not wait for a proxy, workloads that manage their own networking, pods that only talk to things outside the mesh. It also spreads: every manifest copied from that one inherits it, long after the original reason is gone.

### See what the pod template asks for

Print the pod-template labels of the broken workload and of a working one:

```sh
kubectl -n noinject-demo get deploy reporting-service \
  -o jsonpath='{.spec.template.metadata.labels}{"\n"}'
kubectl -n noinject-demo get deploy notification-service-v1 \
  -o jsonpath='{.spec.template.metadata.labels}{"\n"}'
```

You should see something like:

```text
{"app":"reporting-service","sidecar.istio.io/inject":"false"}
{"app":"notification-service","version":"v1"}
```

There is the cause. Notice that the JSONPath reads `.spec.template.metadata.labels`, the pod template, not `.metadata.labels`.

> [!TIP]
> Compare the broken workload with a working one in the same command. A label you do not expect is much easier to spot next to one you do.

## Precedence, stated once

Several settings can apply to one pod. They are resolved in this order, and the first one that applies decides:

| Order | Setting | Result |
| --- | --- | --- |
| 1 | Pod template label `sidecar.istio.io/inject: "false"` | **Not** injected. Beats everything below, because the `objectSelector` excludes the pod |
| 2 | Pod template label `sidecar.istio.io/inject: "true"` | Can opt a pod **in** where the namespace default is off, but only if the namespace is in scope for the webhook at all |
| 3 | Namespace label `istio-injection=enabled` | Injected by the **default** revision. If `istio.io/rev` is also present, this label wins and the revision label is ignored |
| 4 | Namespace label `istio.io/rev=<revision>` | Injected by that revision |
| 5 | Nothing | Not injected |

Rule 3 is the trap, and it is an upgrade trap. During a canary upgrade you label a namespace `istio.io/rev=1-26-0` and expect it to move. If the old `istio-injection=enabled` label is still there, the namespace stays on the default revision, while it looks as if it is pinned to the new one. The symptom is a workload that never moves however often you restart it. The proof is the `ISTIOD` column in `istioctl proxy-status`, still naming the old pod.

The fix is to remove the old label when you add the revision label. That is one command.

## Injection during a control plane outage

One more input to the decision is not a label at all: whether `istiod` answered. The webhook's `failurePolicy` decides what the API server does when the call fails:

| `failurePolicy` | Result | How it looks |
| --- | --- | --- |
| `Fail` (Istio default) | Pod creation is refused | Loud: `FailedCreate` events, rollouts stuck |
| `Ignore` | The pod is created **without** a sidecar | Quiet: the rollout succeeds, the workload is outside the mesh |

`Ignore` produces exactly the state this module is about, with every label correct. If some pods in a namespace have sidecars and some do not, and the labels are the same everywhere, check when the pods without sidecars were created. Then check whether the control plane was healthy at that time.

## Common pitfalls

> [!WARNING]
> - **Putting `sidecar.istio.io/inject` on the Deployment's own `metadata.labels`.** It must be on `spec.template.metadata.labels` to reach a pod. Anywhere else it does nothing.
> - **Setting both namespace labels.** `istio-injection=enabled` beats `istio.io/rev`, so a namespace you believe is pinned to a canary revision is quietly served by the default one.
> - **Expecting a namespace label to override a pod opt-out.** It cannot: the opt-out is enforced by the webhook's `objectSelector`, so `istiod` is never asked.
> - **Expecting "no injection" to leave a trace.** A namespace that matches no webhook selector causes no call and no log line anywhere.
> - **Reading the labels without reading the webhook.** The selectors are the real rule; the labels only matter because the selectors name them.

> *The ship's own opt-out beats every planet setting, and `istio-injection=enabled` beats `istio.io/rev`: in that order, every time.*
