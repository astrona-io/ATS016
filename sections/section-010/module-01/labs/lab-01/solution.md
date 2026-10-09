# Solution: Find And Fix The Configuration Errors

Work the task yourself first, astronaut. Running `astrona submit -c sections/section-010/module-01/labs/lab-01` after a step tells you which checks pass, without telling you what is left.

The grader checks three things: `istioctl analyze` is clean, ten `POST` requests return `200`, and every routed subset exists and selects a running pod.

## Step 1: Reproduce the failure, and rule out the workload

Check the pods and send one request from your test ship:

```sh
kubectl -n analyze-demo get pods
kubectl -n analyze-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

Both pods are `2/2 Running`, and the request returns `503`. A healthy destination with a `503` points at the routing, not at the application. So nothing in the Deployment needs touching.

## Step 2: Ask the analyzer

Run the pre-flight inspector on the namespace:

```sh
istioctl analyze -n analyze-demo
```

```text
Error [IST0101] (VirtualService notification.analyze-demo) Referenced host+subset in destinationrule not found: "notification-service+v3"
Error [IST0101] (VirtualService notification.analyze-demo) Referenced gateway not found: "missing-gateway"
```

There are two `IST0101` findings, both on the same object, and both are references that point at nothing:

- the route names subset `v3`, which no `DestinationRule` defines;
- the object binds to a `Gateway` named `missing-gateway`, which does not exist.

Both are mistakes **between objects**. That is why the API server accepted them: its validating webhook only ever sees the one document being filed.

## Step 3: Decide which end of each reference to fix

Each broken reference can be fixed from either end. Check what is really deployed before you choose:

```sh
kubectl -n analyze-demo get pods --show-labels | grep notification
kubectl -n analyze-demo get destinationrule notification -o jsonpath='{.spec.subsets}{"\n"}'
```

Only `version=v1` pods exist, and the `DestinationRule` defines only `v1`. So:

- **The subset reference:** change the route to `v1`. Adding a `v3` subset would satisfy the analyzer but leave a cluster with no endpoints, a ship class nobody built. The task forbids it, and the grader checks for it.
- **The gateway reference:** remove it. Nothing here is exposed outside the mesh, so the `VirtualService` should apply inside the mesh only. That is the default when `gateways:` is left out.

## Step 4: Apply the corrected VirtualService

Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: analyze-demo
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

The `DestinationRule` stays exactly as it was. It was never the problem.

## Step 5: Prove the fix from both ends

A clean analyze run and a real request answer different questions, and either one alone can mislead you. Check both, and send ten requests instead of one:

```sh
istioctl analyze -n analyze-demo
kubectl -n analyze-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -X POST http://notification-service/notify; done; echo'
```

```text
✔ No validation issues found when analyzing namespace: analyze-demo.
200 200 200 200 200 200 200 200 200 200
```

If you want, confirm that the proxy on the `tester` pod holds the same route as your YAML:

```sh
istioctl proxy-config routes deploy/tester -n analyze-demo -o json \
  | grep '"cluster"' | grep notification
```

```text
"cluster": "outbound|80|v1|notification-service.analyze-demo.svc.cluster.local",
```

The route now points at the `v1` subset cluster, which has running pods behind it.

## Step 6: Submit

Send the mission for grading:

```sh
astrona submit -c sections/section-010/module-01/labs/lab-01
```

## Why the obvious shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Add a `v3` subset to the `DestinationRule` | analyze goes quiet, traffic still fails with `UH`, because no pod carries `version=v3` |
| Create a `Gateway` called `missing-gateway` | analyze goes quiet, and you have added an unused ingress object to satisfy a typo |
| Delete the `DestinationRule` | the subset reference fails in a different way, and the grader requires the `DestinationRule` |
| Restart the Deployment | nothing changes; the workload was never broken |

## Common mistakes

- Treating a clean `kubectl apply` as proof the configuration is correct. It only proves the schema matched.
- Ignoring Warnings. `IST0102` and `IST0103` explain most "my policy does nothing" reports, and they are not Errors.
- Running analyze in the wrong namespace. It looks at one namespace unless you pass `--all-namespaces`.
- Fixing several things at once, then not knowing which change mattered.

## Practice on your own

- Break a `Gateway` reference on purpose and predict the message code before you run analyze.
- Run `istioctl analyze --failure-threshold Warning` and compare the exit code with the default threshold.
- Compare `istioctl validate -f` and `istioctl analyze --use-kube=false` on the same broken file, and explain why only one of them finds the subset error.
