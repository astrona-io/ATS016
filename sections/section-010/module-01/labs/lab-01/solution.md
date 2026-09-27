# Solution: Find And Fix The Configuration Errors In `analyze-demo`

A walkthrough. Work the task yourself first — `astrona submit` after each step
tells you which checks are passing without revealing what is left.

## Step 1 — Reproduce, and confirm it is not the workload

```sh
kubectl -n analyze-demo get pods
kubectl -n analyze-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

Both pods are `2/2 Running`, and the request returns `503`. A healthy
destination and a `503` is the signature of a routing fault, not an application
fault — so nothing in the Deployment needs touching.

## Step 2 — Ask the analyzer

```sh
istioctl analyze -n analyze-demo
```

```text
Error [IST0101] (VirtualService notification.analyze-demo) Referenced host+subset in destinationrule not found: "notification-service+v3"
Error [IST0101] (VirtualService notification.analyze-demo) Referenced gateway not found: "missing-gateway"
```

Two `IST0101` findings, both on the same object, both dangling references:

- the route names subset `v3`, which no `DestinationRule` defines;
- the object binds to a `Gateway` named `missing-gateway`, which does not exist.

Both are **cross-object** mistakes, which is why the API server accepted them:
an admission webhook only ever sees the single document being submitted.

## Step 3 — Decide which end of each reference to fix

Each dangling reference can be resolved from either end. Check reality before
choosing:

```sh
kubectl -n analyze-demo get pods --show-labels | grep notification
kubectl -n analyze-demo get destinationrule notification -o jsonpath='{.spec.subsets}{"\n"}'
```

Only `version=v1` pods exist, and the `DestinationRule` defines only `v1`. So:

- **the subset reference** → change the route to `v1`. Adding a `v3` subset
  would satisfy the analyzer and leave the cluster with no endpoints, turning a
  loud `NC` failure into a quieter `UH` one. The task forbids it, and it is the
  wrong instinct in production too.
- **the gateway reference** → remove it. Nothing here is exposed outside the
  mesh, so the `VirtualService` should apply to the mesh only, which is the
  default when `gateways:` is omitted.

## Step 4 — Apply the corrected VirtualService

```sh
kubectl apply -f - <<'EOF'
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
EOF
```

The `DestinationRule` is left exactly as it was — it was never the problem.

```sh
astrona submit
```

## Step 5 — Verify from both ends

A clean analyze run and a real request answer different questions, and either
alone can mislead you. Check both:

```sh
istioctl analyze -n analyze-demo
kubectl -n analyze-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -X POST http://notification-service/notify; done; echo'
```

```text
✔ No validation issues found when analyzing namespace: analyze-demo.
200 200 200 200 200 200 200 200 200 200
```

Ten requests rather than one: with a single subset behind the Service a lone
`200` could be luck, and the habit matters more on a task with two subsets.

Optionally confirm the proxy agrees with your YAML:

```sh
istioctl proxy-config routes deploy/tester -n analyze-demo -o json \
  | grep '"cluster"' | grep notification
```

```text
"cluster": "outbound|80|v1|notification-service.analyze-demo.svc.cluster.local",
```

```sh
astrona submit
```

## Why the obvious shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Add a `v3` subset to the `DestinationRule` | analyze goes quiet, traffic still fails with `UH` — no pod carries `version=v3` |
| Create a `Gateway` called `missing-gateway` | analyze goes quiet, and you have added an unused ingress object to satisfy a typo |
| Delete the `DestinationRule` | the subset reference now fails differently, and you lose the object the next lab builds on |
| Restart the Deployment | nothing changes; the workload was never broken |

## Common mistakes

- Treating a clean `kubectl apply` as proof the configuration is correct. It
  only proves the schema matched.
- Ignoring Warnings. `IST0102` and `IST0103` explain most "my policy does
  nothing" reports, and they are not Errors.
- Running analyze in the wrong namespace — it is namespace-scoped unless you
  pass `--all-namespaces`.
- Fixing several things at once, then not knowing which change mattered.

## Practice variations

- Break a `Gateway` reference on purpose and predict the message code before
  running analyze.
- Run `istioctl analyze --failure-threshold Warning` and compare the exit code
  with the default threshold.
- Compare `istioctl validate -f` and `istioctl analyze --use-kube=false` on the
  same broken file, and explain why only one of them finds the subset error.
