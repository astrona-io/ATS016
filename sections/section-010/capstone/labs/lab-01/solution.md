# Solution: Repair A Namespace Nothing Validates

Three faults, and only one of them is reported as an `Error`. That is the point
of the capstone: severity describes what Istio *will do*, not how much trouble
you are in.

## Step 1 — Enumerate every finding

```sh
istioctl analyze -n audit-demo
```

```text
Error   [IST0101] (VirtualService notification.audit-demo) Referenced gateway not found: "audit-gateway"
Error   [IST0101] (VirtualService notification.audit-demo) Referenced host+subset in destinationrule not found: "notification-service+v3"
Warning [IST0102] (Namespace audit-demo) The namespace is not enabled for Istio injection...
Info    [IST0103] (Pod notification-service-v1-...) The pod is missing the Istio proxy.
```

Read all the way to the bottom. The `Warning` and the `Info` are the expensive
ones here: a namespace carrying mesh configuration that is not injected means
**every policy in it applies to nothing**.

## Step 2 — Find the fault the analyzer does not report

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

The policy selects `app=notifications`; the pods carry `app=notification-service`.
The selector matches nothing, so the policy is inert — valid, applied, and
enforcing on zero workloads. No analyzer reports this, which is why the task
asks you to read the effective state rather than the intent.

## Step 3 — Label the namespace and recreate the pods

Injection happens at **pod creation only**, so the label alone changes nothing:

```sh
kubectl label namespace audit-demo istio-injection=enabled
kubectl -n audit-demo rollout restart deployment notification-service-v1 tester
kubectl -n audit-demo rollout status deployment/notification-service-v1 --timeout=180s
kubectl -n audit-demo rollout status deployment/tester --timeout=180s
kubectl -n audit-demo get pods -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
```

Both pods now report two containers. Without this step every later fix is
theatre: a policy on a pod with no proxy enforces nothing.

## Step 4 — Fix the two dangling references

Check reality before choosing which end to change:

```sh
kubectl -n audit-demo get pods --show-labels | grep notification
kubectl -n audit-demo get destinationrule notification -o jsonpath='{.spec.subsets}{"\n"}'
```

Only `version=v1` exists, and the `DestinationRule` defines only `v1`. Nothing
is exposed outside the mesh, so the gateway binding is simply wrong:

```sh
kubectl apply -f - <<'EOF'
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
EOF
```

Creating an `audit-gateway` or a `v3` subset would silence the analyzer and
leave the namespace broken — a `Gateway` nobody routes through, and a cluster
with no endpoints.

## Step 5 — Make the policy effective

```sh
kubectl -n audit-demo patch authorizationpolicy notification-post-only --type json \
  -p '[{"op":"replace","path":"/spec/selector/matchLabels/app","value":"notification-service"}]'
```

The method list is left alone — the intent was `POST` only, and the task is to
make that intent real rather than to change it.

```sh
astrona submit
```

## Step 6 — Prove the effective state

```sh
istioctl analyze -n audit-demo
export POD=$(kubectl -n audit-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
istioctl x describe pod $POD -n audit-demo | grep -iE 'RBAC|VirtualService|mTLS'
for M in POST GET; do
  kubectl -n audit-demo exec deploy/tester -- \
    curl -s -o /dev/null -w "$M %{http_code}\n" -X $M http://notification-service/notify
done
```

```text
✔ No validation issues found when analyzing namespace: audit-demo.
RBAC policies: ns[audit-demo]-policy[notification-post-only]-rule[0]
VirtualService: notification
POST 200
GET 403
```

The `RBAC policies` line is the proof the reviewer wanted: the policy now names
this workload. `GET 403` is the proof it is enforcing rather than merely
present.

```sh
astrona submit
```

## What each fault would have cost in production

| Fault | Severity reported | Real consequence |
| --- | --- | --- |
| Namespace not injected | `Warning` | every mesh policy in the namespace applies to nothing |
| Pod without a proxy | `Info` | that workload is outside the mesh entirely |
| Dangling subset reference | `Error` | `503` on every request |
| Dangling gateway reference | `Error` | the object binds to nothing |
| Selector matching no pod | **not reported** | an authorization control that exists on paper only |

## Common mistakes

- Reading only the Errors and declaring the namespace fixed.
- Labelling the namespace and not recreating the pods.
- Creating the missing `Gateway` or subset to make findings disappear.
- Deleting the `AuthorizationPolicy` because `GET` was failing — here it was not
  even the thing refusing.
- Testing only `POST`. A policy that permits everything also passes that test.
