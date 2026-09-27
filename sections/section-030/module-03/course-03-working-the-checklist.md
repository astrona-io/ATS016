# Part 3 — Working The Checklist

> Prerequisite: [Part 2 — Labels, Selectors And Precedence](./course-02-labels-and-precedence.md). Next: [the module landing page](./course.md), then [section 040](../../section-040/module-01/course.md).

Parts 1 and 2 covered the mechanism and the decision inputs. This part is the procedure: six checks in the order that resolves fastest, the remaining four in detail, and then the fix applied and proved on the workload in the playground.

## The checklist

```text
   1. Namespace label      istio-injection / istio.io/rev present?      ← Part 2
   2. Pod template label   sidecar.istio.io/inject: "false"?            ← Part 2
   3. Pod age              was the pod created before the fix?          ← here
   4. Webhook health       does the injector exist and select this ns?  ← here
   5. Revision mismatch    is the named revision actually installed?    ← here
   6. Pod spec             hostNetwork, or another exclusion?           ← here
```

The order is roughly how often each is the answer, and every step is cheap. Work it top to bottom and stop at the first thing that is wrong — but note *which* step stopped you, because that is what tells you whether the fix needs a restart, a label change, or an install change.

## 3. Pod age

Suppose the namespace label had been missing and you had just added it. Nothing happens. From [Part 1](./course-01-the-injection-webhook.md), injection runs at pod creation, so existing pods are unaffected permanently; they need `kubectl rollout restart` or any other recreation before the webhook sees them again.

This is the single most common false conclusion in this area: the labels are now correct, the pod has no sidecar, and the fix was applied twenty minutes ago to pods created yesterday.

The check is a comparison of two timestamps:

```sh
kubectl -n noinject-demo get pods -o custom-columns='POD:.metadata.name,AGE:.metadata.creationTimestamp'
kubectl get ns noinject-demo -o jsonpath='{.metadata.managedFields[*].time}{"\n"}'
```

The second is approximate — it shows when the namespace object was last written, not specifically when the label changed — but a pod older than the namespace's last modification is enough to suspect this step. Your change history (git, or the audit log) is the precise answer.

The rule to carry: **a label change is not complete until the pods are recreated.** In a pipeline, treat "relabel" and "restart" as one operation.

## 4. Webhook health

If the namespace and pod template both look right and a **newly created** pod still has no sidecar, suspect the injector itself. Two things to establish: that the `MutatingWebhookConfiguration` exists, and that its `namespaceSelector` actually matches this namespace's labels.

> [!TIP]
> **Try it — the webhook and what it selects**
>
> ```sh
> kubectl get mutatingwebhookconfiguration | grep -i sidecar-injector
> kubectl get mutatingwebhookconfiguration istio-sidecar-injector \
>   -o jsonpath='{.webhooks[0].namespaceSelector}{"\n"}'
> ```
>
> Expect something like:
>
> ```text
> istio-sidecar-injector   4     12m
> {"matchExpressions":[{"key":"istio.io/rev","operator":"In","values":["default"]},{"key":"istio-injection","operator":"DoesNotExist"}]}
> ```
>
> The `4` in the first line is the number of webhook entries in the configuration — the several branches [Part 2](./course-02-labels-and-precedence.md) described, covering the label combinations between them. The selector shown is entry `[0]`; the others handle the `istio-injection=enabled` case. What you are verifying is that **some** branch matches your namespace's labels, so print them all if entry zero does not.

The second half of webhook health is reachability, which is [module 030-01's](../module-01/course-03-outage-anatomy-and-rejects.md) territory: if `istiod` is unreachable, `failurePolicy` decides whether pod creation is blocked or silently proceeds without a sidecar. The events on the ReplicaSet are where that shows up:

```sh
kubectl -n noinject-demo describe replicaset -l app=reporting-service | tail -20
```

A `failed calling webhook "sidecar-injector.istio.io"` line there is a complete diagnosis and points at the control plane, not at your labels.

## 5. Revision mismatch

With multiple control planes installed, a namespace labelled `istio.io/rev=1-25` is served by the `1-25` revision — and by **nothing at all** if that revision has since been uninstalled. Every object looks configured, the webhook exists, and no pod is ever injected.

The check is whether the named revision is actually present:

```sh
kubectl get ns noinject-demo -o jsonpath='{.metadata.labels.istio\.io/rev}{"\n"}'
kubectl -n istio-system get pods -l app=istiod -L istio.io/rev
istioctl tag list
```

`istioctl tag list` is the one worth knowing about. A **tag** is an alias pointing at a revision — `default` is itself usually a tag — so a namespace can name a stable alias while the revision behind it is swapped during an upgrade. A namespace pointing at a tag that points at nothing produces exactly this failure, and only the tag listing shows the broken link.

The `ISTIOD` column of [`proxy-status`](../module-02/course.md) is the cross-check: it shows which revision is serving workloads that *do* work.

## 6. Pod spec exclusions

A few pods are never injected regardless of labels, and the reasons are mechanical rather than policy:

| Condition | Why |
| --- | --- |
| `hostNetwork: true` | the pod shares the node's network namespace; the `iptables` redirection from Part 1 cannot be applied without affecting the node |
| pods in `kube-system` and similar | excluded by the webhook's `namespaceSelector` in most installs, to avoid breaking the control plane of the cluster itself |
| a pod with no ports and no network needs | injected, but with nothing to intercept — not an exclusion, just an absence of effect |

`hostNetwork` is the one to remember for an exam, and the reasoning is the point: Istio skips it rather than breaking it.

## Fixing the case in front of you

In this namespace the cause was step 2, so the fix is to remove the opt-out and recreate the pod. Both halves are required: removing the label changes the template, and only a new pod goes through the webhook.

The label key contains a `/`, which is the path separator in a JSON Patch, so it has to be escaped as `~1` — that is the one genuinely obscure detail in this command.

> [!TIP]
> **Try it — removing the opt-out**
>
> ```sh
> kubectl -n noinject-demo patch deployment reporting-service --type json \
>   -p '[{"op":"remove","path":"/spec/template/metadata/labels/sidecar.istio.io~1inject"}]'
> kubectl -n noinject-demo rollout status deployment reporting-service --timeout=120s
> ```
>
> Expect something like:
>
> ```text
> deployment.apps/reporting-service patched
> deployment "reporting-service" successfully rolled out
> ```
>
> Patching the **pod template** changes the template hash, so the Deployment creates a new ReplicaSet and therefore new pods — no separate restart was needed. Had the fix been a *namespace* label instead, nothing would have been recreated and `kubectl rollout restart` would have been the necessary second step. That difference is worth internalising: fixes at step 2 recreate pods, fixes at steps 1, 4 and 5 do not.

## Proving it joined

Confirm from two directions, because they are genuinely independent claims. The container list says a proxy exists in the pod. `proxy-status` says that proxy connected to the control plane and received configuration. A pod can pass the first and fail the second — that is the whole of [module 030-02 Part 3](../module-02/course-03-absence-and-per-proxy-diff.md).

> [!TIP]
> **Try it — two proofs that it joined**
>
> ```sh
> kubectl -n noinject-demo get pods -l app=reporting-service \
>   -o jsonpath='{.items[0].spec.containers[*].name}{"\n"}'
> istioctl proxy-status | grep reporting-service
> ```
>
> Expect something like:
>
> ```text
> reporting-service istio-proxy
> reporting-service-5c7d9f684-qv8rz.noinject-demo   Kubernetes   SYNCED   SYNCED   SYNCED   SYNCED   istiod-7d4c9b8f4-k2m8x   1.30.5
> ```
>
> Two containers and a fully synced row. The workload is now subject to every mesh policy in this namespace — which is the actual point of the exercise, and the thing that was silently untrue ten minutes ago.

One more check, and it is not ceremony. Joining the mesh means the workload's traffic is now intercepted, and interception is where two latent configuration problems surface at once: a Service port with no protocol name, and an application bound only to `127.0.0.1`. Both work perfectly without a sidecar and break the moment one appears.

> [!TIP]
> **Try it — traffic still flows**
>
> ```sh
> kubectl -n noinject-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' http://reporting-service/
> istioctl analyze -n noinject-demo
> ```
>
> Expect something like:
>
> ```text
> 200
> ✔ No validation issues found when analyzing namespace: noinject-demo.
> ```
>
> The `200` proves interception did not break the application, and the clean analyze run confirms the `IST0103` from Part 1 is gone. If this had returned a connection failure instead, the cause would be interception meeting an application listening on loopback only — a real and frequent consequence of joining the mesh, and not a reason to leave the workload outside it.

> [!WARNING]
> **Pitfalls in working the checklist**
>
> - **Fixing a label and not recreating the pod.** Steps 1, 4 and 5 all require an explicit `kubectl rollout restart`; only a pod-template change recreates pods by itself.
> - **Reading only webhook entry `[0]`.** A default install has several branches covering different label combinations. Print them all before concluding your namespace matches none.
> - **Trusting a revision label without checking the revision exists.** A namespace pinned to an uninstalled revision, or to a tag pointing nowhere, looks perfectly configured.
> - **Expecting `hostNetwork: true` pods to be injected.** They never are, and no label changes that.
> - **Stopping at "the sidecar is there".** A container that exists is not a proxy that connected. Confirm with `istioctl proxy-status`.
> - **Assuming interception is free.** A newly meshed workload with an unnamed Service port or a loopback-only listener will break at exactly the moment it joins.

> *Work the six checks in order and note which one stopped you — that is what tells you whether the fix needs a restart, a relabel, or an install change.*

## Reference

- [Controlling the injection policy](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/#controlling-the-injection-policy) — the full label matrix, including the `"true"` opt-in case.
- `istioctl tag list` / [safe upgrades with tags](https://istio.io/latest/docs/setup/upgrade/canary/#stable-revision-labels) — revision aliases and the broken-link failure in step 5.
- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — the port-naming rule that bites the moment a workload joins the mesh.
- [Application requirements](https://istio.io/latest/docs/ops/deployment/application-requirements/) — the loopback-binding rule and the other constraints an injected workload must satisfy.
