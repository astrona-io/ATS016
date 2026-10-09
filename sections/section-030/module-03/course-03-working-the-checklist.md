# Working The Checklist

A pod that started without its sidecar proxy can have six different causes. The labels cover the first two; this part is the full procedure, with six checks in the order that finds the answer fastest and the last four explained in detail. Work it from top to bottom and stop at the first thing that is wrong.

## The checklist

Every step is cheap, and the order follows roughly how often each step is the answer:

| Step | Check | Question |
| --- | --- | --- |
| 1 | Namespace label | Is `istio-injection` or `istio.io/rev` present? |
| 2 | Pod template label | Does the pod template carry `sidecar.istio.io/inject: "false"`? |
| 3 | Pod age | Was the pod created before the fix? |
| 4 | Webhook health | Does the injector exist, does it select this namespace, and did `istiod` answer? |
| 5 | Revision mismatch | Is the named revision actually installed? |
| 6 | Pod spec | Is there `hostNetwork: true`, or another exclusion? |

Steps 1 and 2 are about labels: the namespace's injection label, and the pod template's own opt-out, which beats every namespace setting. Note *which* step stopped you, because it tells you whether the fix needs a restart, a label change, or an install change.

## Pod age

Suppose the namespace label had been missing, and you have just added it. Nothing happens. Injection only runs when a pod is created, so existing pods stay as they are. They need `kubectl rollout restart`, or any other way of recreating them, before the webhook sees them. This is the most common false conclusion in this area: the labels are now correct, the pod has no sidecar, and the fix was made twenty minutes ago to pods created yesterday.

<!-- astrona:playground:renew -->

Print when each pod was created, and when the namespace object was last written:

```sh
kubectl -n noinject-demo get pods -o custom-columns='POD:.metadata.name,AGE:.metadata.creationTimestamp'
kubectl get ns noinject-demo -o jsonpath='{.metadata.managedFields[*].time}{"\n"}'
```

The second time is only approximate. It shows when the namespace object was last written, not exactly when the label changed. Still, a pod older than the namespace's last change is enough to suspect this step, and your change history or the cluster's audit log gives the exact answer. The rule to remember is that **a label change is not finished until the pods are recreated.** In a pipeline, treat "relabel" and "restart" as one step.

## Webhook health

If the namespace and the pod template both look right, and a **newly created** pod still has no sidecar, suspect the injector itself. Establish two things: that the `MutatingWebhookConfiguration` exists, and that one of its entries matches this namespace's labels. List the injector and print the namespace selector of its first entry:

```sh
kubectl get mutatingwebhookconfiguration | grep -i sidecar-injector
kubectl get mutatingwebhookconfiguration istio-sidecar-injector \
  -o jsonpath='{.webhooks[0].namespaceSelector}{"\n"}'
```

You should see something like:

```text
istio-sidecar-injector   4     12m
{"matchExpressions":[{"key":"istio.io/rev","operator":"In","values":["default"]},{"key":"istio-injection","operator":"DoesNotExist"}]}
```

The `4` in the first line is the number of webhook entries. Entry `[0]` handles namespaces labelled `istio.io/rev=default` without `istio-injection`; another entry handles `istio-injection=enabled`. You are checking that **some** entry matches your namespace's labels, so print them all if entry `[0]` does not.

The second half of webhook health is whether `istiod` answered. If it did not, the `failurePolicy` decided whether pod creation was blocked or went ahead without a sidecar. The ReplicaSet's events show it:

```sh
kubectl -n noinject-demo describe replicaset -l app=reporting-service | tail -20
```

A `failed calling webhook "sidecar-injector.istio.io"` line there is a complete diagnosis. It points at the control plane, not at your labels. In the playground there is no such line, because `istiod` is healthy.

## Revision mismatch

When several control planes are installed, a namespace labelled `istio.io/rev=1-29` is served by the `1-29` revision. If that revision has since been removed, it is served by **nothing at all**: no webhook entry selects that value, so the API server never calls any `istiod`. Every object looks configured and no pod is ever injected. Print the namespace's revision label, the installed `istiod` pods with their revision, and the revision tags:

```sh
kubectl get ns noinject-demo -o jsonpath='{.metadata.labels.istio\.io/rev}{"\n"}'
kubectl -n istio-system get pods -l app=istiod -L istio.io/rev
istioctl tag list
```

In the playground the first line is empty, because the namespace uses `istio-injection=enabled`. `istioctl tag list` is the command worth knowing. A **tag** is a stable name that points at a revision, and `default` is usually a tag too. A namespace can name a tag while the revision behind it is swapped during an upgrade. A namespace that points at a tag, or a revision, that does not exist produces exactly this failure, and only these commands show the broken link. The `ISTIOD` column of `istioctl proxy-status` is the cross-check: it shows which revision serves the workloads that *do* work.

## Pod spec exclusions

A few pods are never injected, whatever their labels say. The reasons are technical, not policy:

| Condition | Why |
| --- | --- |
| `hostNetwork: true` | The pod shares the node's network, so the `iptables` redirection cannot be applied without changing the node |
| Pods in `kube-system` and similar | Most installs never label these namespaces for injection, so injection cannot break the cluster's own components |
| A pod with no ports and no network needs | It is injected, but there is nothing to intercept. Not an exclusion, just no effect |

Remember `hostNetwork: true` for the exam, together with the reason: Istio skips such a pod rather than change the node's network.

You can now work the full checklist and say what each step rules out. Pod age needs a restart, webhook health and revisions point at the control plane, and pod spec exclusions are deliberate. In the playground the checklist stopped at step 2, the pod-template opt-out. The last question is how to remove it and prove that the workload really joined the mesh.

## Common pitfalls

> [!WARNING]
> - **Fixing a label and not recreating the pod.** A namespace label change, a webhook fix or a revision fix all need an explicit `kubectl rollout restart`.
> - **Reading only webhook entry `[0]`.** A default install has four entries for different label combinations. Print them all before you decide your namespace matches none.
> - **Trusting a revision label without checking that the revision exists.** A namespace pinned to a removed revision, or to a tag that points nowhere, looks perfectly configured.
> - **Expecting `hostNetwork: true` pods to be injected.** They never are, and no label changes that.
