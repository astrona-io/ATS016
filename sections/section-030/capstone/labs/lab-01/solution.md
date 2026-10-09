# Solution: Three Workloads, Three Different Control Plane Faults

Astronaut, the temptation is to find one cause and apply its fix three times. There are three causes, and the checklist is what tells them apart.

## Step 1: Establish the facts for each workload

List the pods in both namespaces with their containers, and take the roll call:

```sh
kubectl -n cpcapstone-demo get pods \
  -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[*].ready,CONTAINERS:.spec.containers[*].name'
kubectl -n cpcapstone-legacy get pods \
  -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
istioctl proxy-status | grep -E 'cpcapstone'
```

```text
orders-service-...     true        orders-service
payments-service-...   true,true   payments-service,istio-proxy
tester-...             true,true   tester,istio-proxy
billing-service-...    true        billing-service

payments-service-...cpcapstone-demo   Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  ...
tester-...cpcapstone-demo             Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  ...
```

Two workloads have one container and no row in `istioctl proxy-status`: no sidecar, so no xDS stream, so no row. `payments-service` **is** meshed and `SYNCED`, which already tells you its problem is something else.

Notice what is healthy, too: `istiod` is running and serving two proxies. This is not one outage with three symptoms.

## Step 2: orders-service, a pod-template opt-out

Work the checklist. Start with the namespace:

```sh
kubectl get ns cpcapstone-demo --show-labels
```

The namespace has `istio-injection=enabled`, which is correct, and the other workloads in the same namespace prove injection works there. So the cause is narrower than the namespace. Check the pod template:

```sh
kubectl -n cpcapstone-demo get deploy orders-service \
  -o jsonpath='{.spec.template.metadata.labels}{"\n"}'
```

```text
{"app":"orders-service","sidecar.istio.io/inject":"false","version":"v1"}
```

The opt-out is on the **pod template**, the only place it matters. It beats the namespace setting, because the injector's `objectSelector` excludes such pods before `istiod` is asked. Remove it:

```sh
kubectl -n cpcapstone-demo patch deployment orders-service --type json \
  -p '[{"op":"remove","path":"/spec/template/metadata/labels/sidecar.istio.io~1inject"}]'
kubectl -n cpcapstone-demo rollout status deployment/orders-service --timeout=180s
```

Patching the template creates a new ReplicaSet, so no separate restart is needed.

## Step 3: billing-service, a revision that does not exist

Same symptom, different namespace, different cause. Check the namespace and the pod template:

```sh
kubectl get ns cpcapstone-legacy --show-labels
kubectl -n cpcapstone-legacy get deploy billing-service \
  -o jsonpath='{.spec.template.metadata.labels}{"\n"}'
```

```text
istio.io/rev=does-not-exist,kubernetes.io/metadata.name=cpcapstone-legacy
{"app":"billing-service","version":"v1"}
```

The pod template is clean. The namespace names a **revision**, a named mission control shift, and nothing answers to that name. List what is installed:

```sh
kubectl -n istio-system get pods -l app=istiod -L istio.io/rev
istioctl tag list
```

The installed control plane is the `default` revision. A namespace pinned to a revision that was never installed, or has since been removed, gets no injection at all, while it looks perfectly configured to anyone reading the labels. Point it at the control plane that exists, and recreate the pods:

```sh
kubectl label namespace cpcapstone-legacy istio.io/rev-
kubectl label namespace cpcapstone-legacy istio-injection=enabled
kubectl -n cpcapstone-legacy rollout restart deployment billing-service
kubectl -n cpcapstone-legacy rollout status deployment/billing-service --timeout=180s
```

Remove the stale revision label rather than leaving both. If `istio-injection` and `istio.io/rev` are both present, `istio-injection` wins and the revision label is quietly ignored, which is how this kind of fault survives an upgrade.

Here the label change does **not** recreate pods, so the explicit `rollout restart` is required. That is the difference from step 2.

## Step 4: payments-service, accepted and never applied

This workload is meshed and `SYNCED`, so injection is not its problem. The complaint was that a `VirtualService` "did nothing". List it, search the `istiod` log, and run the pre-flight inspector:

```sh
kubectl -n cpcapstone-demo get virtualservice
kubectl -n istio-system logs deploy/istiod --tail=200 | grep -i -E 'reject|invalid'
istioctl analyze -n cpcapstone-demo
```

```text
Error [IST0101] ... total destination weight 120 != 100
```

The object exists in etcd, and `istiod` refuses it every time it builds configuration from it. It reached the cluster because the validating webhook was not reachable when it was applied.

`kubectl get` shows it; `kubectl describe` shows no events, because Istio networking objects carry no status conditions. Only the `istiod` log, the `pilot_total_xds_rejects` counter and the analyzer know. Remove it:

```sh
kubectl -n cpcapstone-demo delete virtualservice payments-split
```

Correcting the weights so they add up to 100 is also accepted.

Submit to see your progress:

```sh
astrona submit
```

## Step 5: Verify all three together

Take the roll call, send a real request to `payments-service`, and run the inspector:

```sh
istioctl proxy-status | grep -E 'cpcapstone'
kubectl -n cpcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://payments-service/get
istioctl analyze -n cpcapstone-demo -n cpcapstone-legacy 2>/dev/null || istioctl analyze --all-namespaces
```

```text
billing-service-...cpcapstone-legacy   Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  ...
orders-service-...cpcapstone-demo      Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  ...
payments-service-...cpcapstone-demo    Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  ...
tester-...cpcapstone-demo              Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  ...
200
```

Submit for the final grade:

```sh
astrona submit
```

## The three causes side by side

| Workload | Cause | Where the checklist stopped | Does the fix recreate pods? |
| --- | --- | --- | --- |
| `orders-service` | Pod-template opt-out | Step 2 | **Yes**: patching the template does it |
| `billing-service` | Namespace pinned to a missing revision | Step 5 | **No**: it needs an explicit restart |
| `payments-service` | Invalid configuration stored while the webhook was down | Not an injection fault at all | Not applicable |

Noting *which* step stopped you tells you whether the fix needs a restart, a relabel, or an install change.

## Common mistakes

- Applying one fix to all three workloads. The symptom is shared; the causes are not.
- Fixing a namespace label and not restarting the workload.
- Leaving both `istio-injection` and `istio.io/rev` on a namespace.
- Looking for the rejected configuration in the `kubectl apply` output. The apply succeeded; the rejection happened later, inside `istiod`.
- Deciding the control plane is broken because two workloads are missing from `istioctl proxy-status`. `payments-service` being `SYNCED` rules that out straight away.

## Practice variations

- Scale `istiod` to zero, try to create a pod, and explain the error with the injector webhook's `failurePolicy`.
- Install a second revision, move one namespace to it, and confirm the move with the `ISTIOD` column of `istioctl proxy-status`.
- Set the injector's `failurePolicy` to `Ignore`, take `istiod` down, and see how much quieter the failure is.
