# Solution: Bring An Exempt Workload Back Into The Mesh

Astronaut, one ship on this planet flies without its communications officer. This walkthrough finds it with two checks, works the checklist to the cause, removes it, and proves the ship joined the mesh and still answers.

## Step 1: Find the workload that is not in the mesh

List each pod with its ready flags and container names:

```sh
kubectl -n noinject-demo get pods \
  -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[*].ready,CONTAINERS:.spec.containers[*].name'
```

```text
POD                                       READY        CONTAINERS
notification-service-v1-6c9f8b7d5-x2kqp   true,true    notification-service,istio-proxy
reporting-service-7fd4c8b96-mn5tp         true         reporting-service
tester-6d9f7b8c5-hj4kz                    true,true    tester,istio-proxy
```

One container where the others have two. Nothing here is an error, which is exactly why this state survives reviews.

The second, independent check comes from the mesh's side. Run the pre-flight inspector:

```sh
istioctl analyze -n noinject-demo
```

```text
Info [IST0103] (Pod reporting-service-...) The pod is missing the Istio proxy.
```

`Info` severity, the lowest there is, for a workload exempt from every policy in the namespace. Always read the analyzer output to the bottom.

## Step 2: Work the checklist in order

**1. Namespace label.** Check what the planet asks for:

```sh
kubectl get ns noinject-demo --show-labels
```

```text
istio-injection=enabled,kubernetes.io/metadata.name=noinject-demo
```

Correct. The most common cause is ruled out in one command.

**2. Pod template label.** Compare the broken workload with a working one:

```sh
kubectl -n noinject-demo get deploy reporting-service \
  -o jsonpath='{.spec.template.metadata.labels}{"\n"}'
kubectl -n noinject-demo get deploy notification-service-v1 \
  -o jsonpath='{.spec.template.metadata.labels}{"\n"}'
```

```text
{"app":"reporting-service","sidecar.istio.io/inject":"false"}
{"app":"notification-service","version":"v1"}
```

There is the cause. The opt-out sits on `spec.template.metadata.labels`, the **pod template**, which is the only place it has any effect. It beats the namespace setting, because the webhook's `objectSelector` excludes such pods before `istiod` is ever asked.

Steps 3 and 4 (pod age and webhook health) are not needed once step 2 gives the answer. They would be the next checks if it had not.

## Step 3: Remove the opt-out

The label key contains a `/`, which separates the parts of a JSON Patch path, so it must be written as `~1`:

```sh
kubectl -n noinject-demo patch deployment reporting-service --type json \
  -p '[{"op":"remove","path":"/spec/template/metadata/labels/sidecar.istio.io~1inject"}]'
kubectl -n noinject-demo rollout status deployment/reporting-service --timeout=180s
```

Patching the **pod template** changes its hash, so a new ReplicaSet and new pods are created automatically. No separate `rollout restart` is needed here. A fix to a *namespace* label would have needed one.

Submit to see your progress:

```sh
astrona submit
```

## Step 4: Prove it joined, and that it still works

Check the container, the roll call, a real request, and the inspector:

```sh
kubectl -n noinject-demo get pods -l app=reporting-service \
  -o jsonpath='{.items[0].spec.containers[*].name}{"\n"}'
istioctl proxy-status | grep reporting-service
kubectl -n noinject-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://reporting-service/
istioctl analyze -n noinject-demo
```

```text
reporting-service istio-proxy
reporting-service-...noinject-demo   Kubernetes   SYNCED   SYNCED   SYNCED   SYNCED   ...
200
✔ No validation issues found when analyzing namespace: noinject-demo.
```

On Kubernetes 1.28 and later the proxy can run as a native sidecar, listed under `initContainers`. If the first command prints only `reporting-service`, read `.spec.initContainers[*].name` as well; the grader checks both lists.

The `200` matters as much as the sidecar. Joining the mesh means the traffic is now intercepted, and interception is where two hidden problems appear at once: a Service port with no protocol name, and an application listening only on `127.0.0.1`. Both work without a sidecar and break the moment one arrives.

Submit for the final grade:

```sh
astrona submit
```

## Common mistakes

- Fixing the namespace label but not restarting the workload. Nothing changes, and the fix looks wrong.
- Missing the pod-template opt-out because you looked at the Deployment's own `metadata.labels` instead of the template.
- Leaving a namespace with both `istio-injection` and `istio.io/rev`. The revision label is ignored, which breaks canary upgrades.
- Assuming the whole mesh is broken when only one workload is affected. Compare with a working pod in the same namespace first.
- Stopping at "the sidecar is there". A container that exists is not a proxy that connected.

## Practice variations

- Delete the namespace label instead, and reproduce a different root cause.
- Pin the namespace to a revision that does not exist, and watch what happens.
- Set `hostNetwork: true` on a pod, and explain why injection is skipped.
