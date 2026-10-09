# Working The Checklist

Astronaut, a ship launched without its communications officer can have six different causes. This part is the procedure: six checks in the order that finds the answer fastest, with the last four explained in detail. Work it top to bottom and stop at the first thing that is wrong.

## The checklist

Every step is cheap, and the order follows roughly how often each step is the answer.

| Step | Check | Question |
| --- | --- | --- |
| 1 | Namespace label | Is `istio-injection` or `istio.io/rev` present? |
| 2 | Pod template label | Does the pod template carry `sidecar.istio.io/inject: "false"`? |
| 3 | Pod age | Was the pod created before the fix? |
| 4 | Webhook health | Does the injector exist, and does it select this namespace? |
| 5 | Revision mismatch | Is the named revision actually installed? |
| 6 | Pod spec | Is there `hostNetwork`, or another exclusion? |

Steps 1 and 2 are about labels: the planet's injection label, and the ship's own opt-out on its pod template. The ship's own opt-out beats every namespace setting. Note *which* step stopped you, because that tells you whether the fix needs a restart, a label change, or an install change.

## 3. Pod age

Imagine the namespace label had been missing, and you have just added it. Nothing happens. Injection only runs when a pod is created, so existing pods stay as they are for good. They need `kubectl rollout restart`, or any other way of recreating them, before the webhook sees them again.

This is the most common false conclusion in this area. The labels are now correct, the pod has no sidecar, and the fix was made twenty minutes ago to pods created yesterday.

<!-- astrona:playground:renew -->

### Compare pod age with the namespace's last change

Print when each pod was created, and when the namespace object was last written:

```sh
kubectl -n noinject-demo get pods -o custom-columns='POD:.metadata.name,AGE:.metadata.creationTimestamp'
kubectl get ns noinject-demo -o jsonpath='{.metadata.managedFields[*].time}{"\n"}'
```

The second time is only approximate. It shows when the namespace object was last written, not exactly when the label changed. Still, a pod older than the namespace's last change is enough to suspect this step. Your change history (git, or the cluster's audit log) gives the exact answer.

The rule to remember: **a label change is not finished until the pods are recreated.** In a pipeline, treat "relabel" and "restart" as one step.

## 4. Webhook health

If the namespace and the pod template both look right, and a **newly created** pod still has no sidecar, suspect the injector itself. Establish two things: that the `MutatingWebhookConfiguration` exists, and that its `namespaceSelector` matches this namespace's labels.

### Check the webhook and what it selects

List the injector and print the namespace selector of its first entry:

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

The `4` in the first line is the number of webhook entries in the configuration. Between them, these entries cover the different label combinations. The selector shown is entry `[0]`; the others handle the `istio-injection=enabled` case. You are checking that **some** entry matches your namespace's labels, so print them all if entry zero does not.

### Check that the webhook was reachable

The second half of webhook health is whether `istiod` answered. If it did not, the `failurePolicy` decides whether pod creation was blocked or went ahead without a sidecar. The ReplicaSet's events show it:

```sh
kubectl -n noinject-demo describe replicaset -l app=reporting-service | tail -20
```

A `failed calling webhook "sidecar-injector.istio.io"` line there is a complete diagnosis. It points at the control plane, not at your labels.

## 5. Revision mismatch

When several control planes are installed, a namespace labelled `istio.io/rev=1-25` is served by the `1-25` revision. If that revision has since been removed, it is served by **nothing at all**. Every object looks configured, the webhook exists, and no pod is ever injected. In space terms, the planet is tied to a mission control shift that no longer exists, so no ship gets an officer.

### Check that the named revision exists

Print the namespace's revision label, the installed `istiod` pods with their revision, and the revision tags:

```sh
kubectl get ns noinject-demo -o jsonpath='{.metadata.labels.istio\.io/rev}{"\n"}'
kubectl -n istio-system get pods -l app=istiod -L istio.io/rev
istioctl tag list
```

`istioctl tag list` is the one worth knowing. A **tag** is an alias that points at a revision; `default` is itself usually a tag. A namespace can name a stable alias while the revision behind it is swapped during an upgrade. A namespace that points at a tag that points at nothing produces exactly this failure, and only the tag list shows the broken link.

The `ISTIOD` column of `istioctl proxy-status` is the cross-check. It shows which revision serves the workloads that *do* work.

## 6. Pod spec exclusions

A few pods are never injected, whatever their labels say. The reasons are mechanical, not policy:

| Condition | Why |
| --- | --- |
| `hostNetwork: true` | The pod shares the node's network, so the `iptables` redirection cannot be applied without changing the node |
| Pods in `kube-system` and similar | Most installs exclude them in the webhook's `namespaceSelector`, so injection cannot break the cluster's own control plane |
| A pod with no ports and no network needs | It is injected, but there is nothing to intercept. Not an exclusion, just no effect |

Remember `hostNetwork` for the exam, together with the reason: Istio skips such a pod rather than break the node.

## Common pitfalls

> [!WARNING]
> - **Fixing a label and not recreating the pod.** A namespace label change, a webhook fix or a revision fix all need an explicit `kubectl rollout restart`.
> - **Reading only webhook entry `[0]`.** A default install has several entries for different label combinations. Print them all before you decide your namespace matches none.
> - **Trusting a revision label without checking that the revision exists.** A namespace pinned to a removed revision, or to a tag that points nowhere, looks perfectly configured.
> - **Expecting `hostNetwork: true` pods to be injected.** They never are, and no label changes that.

> *Work the six checks in order and note which one stopped you: that tells you whether the fix needs a restart, a relabel or an install change.*
