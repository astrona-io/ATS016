# Solution: Bring An Exempt Workload Back Into The Mesh

One workload in this namespace runs without its sidecar proxy. This walkthrough finds it with two checks, works the checklist to the cause, removes it, and proves the workload joined the mesh and still answers.

## Step 1: Find the workload that is not in the mesh

List each pod with its containers and its init containers. The lab's node runs Kubernetes 1.33 or later, so Istio 1.30 adds `istio-proxy` as a native sidecar under `initContainers`:

```sh
kubectl -n noinject-demo get pods \
  -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name,INIT:.spec.initContainers[*].name'
```

The `CONTAINERS` column shows only the application for every pod. The `INIT` column lists `istio-proxy` for `notification-service-v1` and `tester`, and nothing for `reporting-service`. Nothing here is an error, which is exactly why this state survives reviews. The `READY` column of plain `kubectl get pods` shows the same difference: `1/1` against `2/2`.

The second, independent check comes from `istiod`'s side:

```sh
istioctl proxy-status | grep noinject-demo
```

The output lists `notification-service-v1` and `tester`, and no row for `reporting-service`, because it has no proxy to connect. `istioctl analyze -n noinject-demo` does not help here: it reports `IST0103` only for pods that lack a proxy without opting out, so it skips a deliberate opt-out.

## Step 2: Work the checklist in order

**1. Namespace label.** Check what the namespace asks for:

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

There is the cause. The opt-out sits on `spec.template.metadata.labels`, the **pod template**, which is the only place it has any effect. It beats the namespace setting, because the webhook's `objectSelector` excludes such pods before `istiod` is ever asked. Steps 3 and 4, pod age and webhook health, are not needed once step 2 gives the answer.

## Step 3: Remove the opt-out

The label key contains a `/`, which separates the parts of a JSON Patch path, so it must be written as `~1`:

```sh
kubectl -n noinject-demo patch deployment reporting-service --type json \
  -p '[{"op":"remove","path":"/spec/template/metadata/labels/sidecar.istio.io~1inject"}]'
kubectl -n noinject-demo rollout status deployment/reporting-service --timeout=180s
```

Patching the **pod template** changes its hash, so a new ReplicaSet and new pods are created automatically. No separate `rollout restart` is needed here; a fix to a *namespace* label would have needed one.

Submit to see your progress:

```sh
astrona submit
```

## Step 4: Prove it joined, and that it still works

Check the sidecar, the sync state, a real request, and the analyzer:

```sh
kubectl -n noinject-demo get pods -l app=reporting-service \
  -o jsonpath='{.items[0].spec.containers[*].name}{"  init: "}{.items[0].spec.initContainers[*].name}{"\n"}'
istioctl proxy-status -v 1 | grep reporting-service
kubectl -n noinject-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://reporting-service/
istioctl analyze -n noinject-demo
```

The first line now lists `istio-proxy` after `init:`. The rest looks like this:

```text
reporting-service-...noinject-demo   Kubernetes   SYNCED (30s)   IGNORED   SYNCED (30s)   SYNCED (30s)   SYNCED (30s)   ...
200
✔ No validation issues found when analyzing namespace: noinject-demo.
```

If the first command prints only `reporting-service`, the proxy runs as a native sidecar; read `.spec.initContainers[*].name` as well. The grader checks both lists. Since Istio 1.27, plain `istioctl proxy-status` shows no per-type sync state, so use `-v 1`.

The `200` matters as much as the sidecar. Joining the mesh means the traffic is now intercepted, and interception is where two hidden problems appear: a Service port with no protocol name, and an application listening only on `127.0.0.1`. Both work without a sidecar and break the moment one arrives.

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

- Delete the namespace label instead, and reproduce a different cause.
- Pin the namespace to a revision that does not exist, and watch what happens.
- Set `hostNetwork: true` on a pod, and explain why injection is skipped.
