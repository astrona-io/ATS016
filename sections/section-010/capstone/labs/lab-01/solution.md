# Solution: Repair A Namespace Nothing Validates

This namespace has three faults, and the analyzer reports only one of them as an `Error`. That is the point of the capstone: severity describes what Istio *will do* with an object, not how much trouble you are in.

The grader checks four things: no `Error` or `Warning` from `istioctl analyze`, an injection label plus a sidecar in every running pod, a policy that selects running pods and allows exactly `POST`, and real traffic (`POST` gets `200`, `GET` gets `403`).

## Step 1: List every finding

Run the analyzer on the namespace:

```sh
istioctl analyze -n audit-demo
```

You should see something like this (shortened; the order can differ):

```text
Error   [IST0101] (VirtualService notification.audit-demo) Referenced gateway not found: "audit-gateway"
Error   [IST0101] (VirtualService notification.audit-demo) Referenced host+subset in destinationrule not found: "notification-service+v3"
Info    [IST0102] (Namespace audit-demo) The namespace is not enabled for Istio injection...
```

Read all the way to the bottom. The `Info` line is the expensive one here. A namespace without the injection label gets no sidecar proxies, so **every Istio policy in the namespace applies to nothing**. Notice that there is no `IST0103` for the pods yet: the analyzer only checks pods for a missing proxy in namespaces that have injection switched on.

## Step 2: Find the fault the analyzer does not report

Compare the policy's selector with the labels the pods really carry:

```sh
kubectl -n audit-demo get pods \
  -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
kubectl -n audit-demo get authorizationpolicy notification-post-only \
  -o jsonpath='{.spec.selector}{"\n"}'
kubectl -n audit-demo get pods --show-labels | grep notification
```

```text
notification-service-v1-...   notification-service
{"matchLabels":{"app":"notifications"}}
notification-service-v1-...   app=notification-service,version=v1
```

The policy selects `app=notifications`, but the pods carry `app=notification-service`. The selector matches nothing, so the policy is valid, applied, and enforced on zero workloads. No analyzer reports this, which is why the task asks you to read the effective state instead of the intent.

## Step 3: Label the namespace and recreate the pods

The sidecar injection webhook, a mutating admission webhook run by `istiod`, adds the `istio-proxy` container only when a pod is **created**. So the label alone changes nothing for pods that already run; if you run the analyzer between the label and the restart, it now reports `IST0103` (a `Warning`) for each pod without a proxy. Label the namespace, then restart both Deployments:

```sh
kubectl label namespace audit-demo istio-injection=enabled
kubectl -n audit-demo rollout restart deployment notification-service-v1 tester
kubectl -n audit-demo rollout status deployment/notification-service-v1 --timeout=180s
kubectl -n audit-demo rollout status deployment/tester --timeout=180s
kubectl -n audit-demo get pods -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
```

Both new pods now carry an `istio-proxy` sidecar. On Kubernetes 1.28 and later the sidecar can be listed under `initContainers` with `restartPolicy: Always` instead of under `containers`, so the custom columns above may not show it. `kubectl -n audit-demo get pods` then shows `2/2` in the `READY` column. Without this step every later fix is for show: a policy on a pod with no proxy enforces nothing.

## Step 4: Fix the two references that point at nothing

Check what is really deployed before you choose which end to change:

```sh
kubectl -n audit-demo get pods --show-labels | grep notification
kubectl -n audit-demo get destinationrule notification -o jsonpath='{.spec.subsets}{"\n"}'
```

Only `version=v1` exists, and the `DestinationRule` defines only `v1`. Nothing is exposed outside the mesh, so the gateway binding is simply wrong. Route to `v1` and drop the `gateways:` list.

Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: audit-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
            subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

Creating an `audit-gateway` or a `v3` subset would quiet the analyzer and leave the namespace broken: a `Gateway` nobody routes through, and a cluster with no endpoints.

## Step 5: Make the policy effective

Point the policy's selector at the label the pods really carry:

```sh
kubectl -n audit-demo patch authorizationpolicy notification-post-only --type json \
  -p '[{"op":"replace","path":"/spec/selector/matchLabels/app","value":"notification-service"}]'
```

The method list stays as it is. The intent was `POST` only, and the task is to make that intent real, not to change it.

## Step 6: Prove the effective state

Run the analyzer, read the effective configuration of the `notification-service` pod with `istioctl x describe pod`, and send both methods from the `tester` pod:

```sh
istioctl analyze -n audit-demo
export POD=$(kubectl -n audit-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
istioctl x describe pod $POD -n audit-demo | grep -E '^(RBAC policies|VirtualService):'
for M in POST GET; do
  kubectl -n audit-demo exec deploy/tester -- \
    curl -s -o /dev/null -w "$M %{http_code}\n" -X $M http://notification-service/notify
done
```

```text
✔ No validation issues found when analyzing namespace: audit-demo.
VirtualService: notification
RBAC policies: ns[audit-demo]-policy[notification-post-only]-rule[0]
POST 200
GET 403
```

The `RBAC policies` line is the proof the reviewer wanted: the policy now names this workload. `GET 403` proves it is enforcing, not just present.

## Step 7: Submit

Send the capstone for grading:

```sh
astrona submit -c sections/section-010/capstone/labs/lab-01
```

## What each fault would have cost in production

| Fault | Severity reported | Real consequence |
| --- | --- | --- |
| Namespace not injected | `Info` (`IST0102`) | every Istio policy in the namespace applies to nothing |
| Pod without a proxy | `Warning` (`IST0103`), only once the namespace is labelled | that workload is outside the mesh entirely |
| Subset reference that points at nothing | `Error` | `503` on every request |
| Gateway reference that points at nothing | `Error` | the object binds to nothing |
| Selector matching no pod | **not reported** | an authorization control that exists on paper only |

## Common mistakes

- Reading only the `Error` lines and declaring the namespace fixed.
- Labelling the namespace and not recreating the pods.
- Creating the missing `Gateway` or subset to make findings disappear.
- Deleting the `AuthorizationPolicy` because `GET` was failing. Here it was not even the thing refusing.
- Testing only `POST`. A policy that allows everything also passes that test.
