# Labels, Selectors And Precedence

The injection webhook decides, when a pod is created, whether the pod gets a sidecar proxy. This part covers that decision: which labels take part, where they live, and what happens when several of them disagree. Getting the order right is the difference between fixing an injection problem with one command and changing labels until something works.

## Two namespace labels, not one

A namespace asks for injection with one of two labels, and they are not the same thing:

| Label | Means | Used when |
| --- | --- | --- |
| `istio-injection=enabled` | Inject using the **default** control plane revision | A single Istio install with no named versions |
| `istio.io/rev=<revision>` | Inject using the named **revision** | Several `istiod` revisions run side by side, for example during a canary upgrade |

If neither label is present, the namespace's pods are not injected, except for single pods that opt in themselves. A revision is one `istiod` installation with its own name. The revision label is not another spelling of the first label: it names *which control plane* serves the workloads. The injected proxy is configured by that revision, connects to that revision's `istiod`, and shows that `istiod` pod in the `ISTIOD` column of `istioctl proxy-status`.

<!-- astrona:playground:renew -->

Show the labels on the playground's namespace:

```sh
kubectl get ns noinject-demo --show-labels
```

You should see something like:

```text
NAME            STATUS   AGE   LABELS
noinject-demo   Active   11m   istio-injection=enabled,kubernetes.io/metadata.name=noinject-demo
```

The namespace is labelled correctly, so that is not the cause here. Ruling out the most common explanation in one command is worth as much as finding a fault. Notice also what is missing: there is no `istio.io/rev`, so the default control plane serves this namespace.

## What the webhook itself selects on

The labels only matter because a `MutatingWebhookConfiguration` selects on them. That object registers the injection webhook with the API server and says which pods it applies to. Reading it turns the convention into a rule you can check. Start with the configuration whose name sounds right, `istio-sidecar-injector`, and print each webhook entry with its namespace selector and its object selector:

```sh
kubectl get mutatingwebhookconfiguration istio-sidecar-injector \
  -o jsonpath='{range .webhooks[*]}{.name}{"\n  ns: "}{.namespaceSelector}{"\n  obj: "}{.objectSelector}{"\n"}{end}'
```

You should see something like:

```text
rev.namespace.sidecar-injector.istio.io
  ns: {"matchLabels":{"istio.io/deactivated":"never-match"}}
  obj: {"matchLabels":{"istio.io/deactivated":"never-match"}}
rev.object.sidecar-injector.istio.io
  ns: {"matchLabels":{"istio.io/deactivated":"never-match"}}
  obj: {"matchLabels":{"istio.io/deactivated":"never-match"}}
namespace.sidecar-injector.istio.io
  ns: {"matchLabels":{"istio.io/deactivated":"never-match"}}
  obj: {"matchLabels":{"istio.io/deactivated":"never-match"}}
object.sidecar-injector.istio.io
  ns: {"matchLabels":{"istio.io/deactivated":"never-match"}}
  obj: {"matchLabels":{"istio.io/deactivated":"never-match"}}
```

Every entry selects on the label `istio.io/deactivated: never-match`, which no namespace or pod carries. This configuration is switched off on purpose. The install also created a **revision tag** called `default`, a name that points at an installed `istiod` revision, and the tag has its own configuration, `istio-revision-tag-default`. That one does the real injection, with the same four entries and working selectors. List every mutating webhook configuration, then print the entries of the tag's configuration:

```sh
kubectl get mutatingwebhookconfiguration
kubectl get mutatingwebhookconfiguration istio-revision-tag-default \
  -o jsonpath='{range .webhooks[*]}{.name}{"\n  ns: "}{.namespaceSelector}{"\n  obj: "}{.objectSelector}{"\n"}{end}'
```

The list shows both `istio-sidecar-injector` and `istio-revision-tag-default`. The tag's entries carry the real selectors: four webhook entries, one for each combination of labels. Between them, the two selectors work like this:

| Selector | Question it answers | Result |
| --- | --- | --- |
| `namespaceSelector` | Should `istiod` even be asked about pods in this namespace? | Yes if the namespace has `istio-injection=enabled`, or `istio.io/rev` naming this revision without `istio-injection`, or no injection label at all for the entries that look at the pod's own label |
| `objectSelector` | Should `istiod` be asked about **this** pod? | Never for pods labelled `sidecar.istio.io/inject=false`; in a namespace with no injection label, only for pods labelled `sidecar.istio.io/inject=true` or `istio.io/rev` |

Two facts follow that are easy to miss. First, a namespace that matches no webhook entry is not "injection disabled"; it is invisible to the injector. The API server never calls `istiod`, so nothing is logged anywhere. There is no error to find, because no call happened. Second, the `sidecar.istio.io/inject=false` exclusion is built into every entry's `objectSelector`, which is why it is absolute: the webhook is never called for that pod, so no namespace setting can override it.

## The pod-template opt-out

A pod can refuse injection, even in a namespace where injection is on, with the label `sidecar.istio.io/inject: "false"`. Where that label sits is the part people get wrong. A Deployment has two sets of labels. Its own labels, in `metadata.labels`, describe the Deployment object. The pod template's labels, in `spec.template.metadata.labels`, are copied to every pod it creates. The webhook sees pods, so only the pod template's labels count. An opt-out in the Deployment's own `metadata.labels` does nothing at all, and believing it works is a way to think a workload is excluded when it is not.

The opt-out exists for good reasons: jobs that must not wait for a proxy, workloads that manage their own networking, pods that only talk to things outside the mesh. It also spreads: every manifest copied from that one inherits it, long after the original reason is gone. Print the pod-template labels of the workload outside the mesh and of a working one:

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

Several settings can apply to one pod. The webhook entries resolve them in this order, and the first one that applies decides:

| Order | Setting | Result |
| --- | --- | --- |
| 1 | Pod label `sidecar.istio.io/inject: "false"` | **Not** injected. Beats everything below, because every entry's `objectSelector` excludes the pod |
| 2 | Namespace label `istio-injection=enabled` | Injected by the **default** revision. If `istio.io/rev` is also present, this label wins and the revision label is ignored |
| 3 | Namespace label `istio.io/rev=<revision>` | Injected by that revision |
| 4 | Namespace label `istio-injection` with any other value, such as `disabled` | Not injected, and a pod label cannot opt back in |
| 5 | No injection label on the namespace, pod label `sidecar.istio.io/inject: "true"` or `istio.io/rev=<revision>` | Only that pod is injected |
| 6 | Nothing | Not injected |

Row 2 is the trap, and it is an upgrade trap. During a canary upgrade you label a namespace `istio.io/rev=<new revision>` and expect it to move. If the old `istio-injection=enabled` label is still there, the namespace stays on the default revision, while it looks as if it is pinned to the new one. The symptom is a workload that never moves however often you restart it, and the proof is the `ISTIOD` column in `istioctl proxy-status`, still naming the old pod. The fix is one command: remove the old label when you add the revision label.

## Injection during a control plane outage

One more input to the decision is not a label at all: whether `istiod` answered. The webhook's `failurePolicy` decides what the API server does when the call fails:

| `failurePolicy` | Result | How it looks |
| --- | --- | --- |
| `Fail` (Istio default) | Pod creation is refused | Loud: `FailedCreate` events, rollouts stuck |
| `Ignore` | The pod is created **without** a sidecar | Quiet: the rollout succeeds, and the workload is outside the mesh |

`Ignore` produces exactly the state this module is about, with every label correct. If some pods in a namespace have sidecars and some do not, and the labels are the same everywhere, check when the pods without sidecars were created. Then check whether the control plane was healthy at that time.

You now know the labels that decide injection, the webhook selectors that read them, and the order in which they win: the pod's own opt-out first, then `istio-injection`, then `istio.io/rev`. In the playground the answer is already clear, because `reporting-service` opts out in its pod template. When the labels are all correct, the cause is one of the remaining checks: pod age, webhook health, revisions or the pod spec.

## Common pitfalls

> [!WARNING]
> - **Putting `sidecar.istio.io/inject` on the Deployment's own `metadata.labels`.** It must be on `spec.template.metadata.labels` to reach a pod.
> - **Setting both namespace labels.** `istio-injection=enabled` beats `istio.io/rev`, so a namespace you believe is pinned to a canary revision is served by the default one.
> - **Expecting a namespace label to override a pod opt-out.** It cannot: the opt-out is in the webhook's `objectSelector`, so `istiod` is never asked.
> - **Expecting a pod's `inject: "true"` label to beat `istio-injection=disabled`.** A pod can only opt in when its namespace has no injection label at all.
> - **Expecting "no injection" to leave a trace.** A namespace that matches no webhook entry causes no call and no log line anywhere.
