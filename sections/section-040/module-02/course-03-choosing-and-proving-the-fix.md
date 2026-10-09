# Choosing And Proving The Fix

Astronaut, a dangling reference can always be resolved from either end: build the target, or stop pointing at it. Only one of those is right in any given case. Choose wrong, and you get a configuration that satisfies the analyzer while the signals still fail. This part makes the choice explicit, applies the fix, and proves it from three directions.

## Two fixes, one correct

The `VirtualService` names `subset: v2`. The `DestinationRule` defines only `v1`. Two different edits would make the reference resolve, and this section shows which one matches reality.

### Option A: route to a subset that exists

Change the `VirtualService` to `subset: v1`.

This is right when the `v2` reference was a mistake, which is the usual case: a manifest copied from an environment where `v2` was deployed, a version rolled back without updating the routing, or a subset renamed on one side only.

### Option B: define the missing subset

Add `v2` to the `DestinationRule`.

This is right **only if pods labelled `version: v2` actually exist**. Here they do not: the planet runs one Deployment labelled `version: v1`. Adding the subset anyway is like adding a ship class to the docking instructions when no ship of that class was ever built.

### What the wrong choice looks like

Choosing Option B wrongly looks like progress, which is what makes it dangerous:

```text
   before:   route → v2,  no v2 cluster          →  503, flag NC
                                                     "the cluster does not exist"

   add a v2 subset whose labels match no pod:

   after:    route → v2,  v2 cluster exists      →  503, flag UH
             cluster has NO endpoints                "no healthy upstream host"
```

The analyzer goes quiet: `IST0101` is satisfied, because the reference now resolves. The traffic still fails. And the diagnosis is now *harder*, because the loud, clear "this does not exist" has turned into the vaguer "there is nothing behind it". An empty cluster has four possible causes (Service selector, readiness, subset labels, ejected endpoints) instead of one.

The rule: **make the reference true in the direction that matches reality.** Check what is deployed before you invent a target for it.

<!-- astrona:playground:renew -->

### Check what is really deployed

List the app's pods with their labels:

```sh
kubectl -n fivezerothree-demo get pods --show-labels | grep notification
```

Only pods with `version=v1` exist. One command, and it decides the fix: the route is wrong, not the `DestinationRule`.

## Applying it

Rewrite the `VirtualService` so it routes to the subset that exists. Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: fivezerothree-demo
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

```text
virtualservice.networking.istio.io/notification configured
```

Then check the result with one signal from the test ship:

```sh
kubectl -n fivezerothree-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

```text
200
```

The fix took effect within a second or two, and no pod restarted. `istiod` (mission control) turned the `VirtualService` change into new route orders and radioed them to the proxy over its open xDS stream, and the proxy swapped its route table in place. If a routing change ever *does* seem to need a restart, the problem is delivery, and `istioctl proxy-status` is the next command, not `kubectl rollout restart`.

## Proving it from three directions

A `200` is good evidence, but not complete evidence. Three sources were wrong at the start, and all three should now agree:

| Source | Proves |
| --- | --- |
| a real request | the behaviour is right **now** |
| the proxy's route table | the proxy holds what you think it holds |
| `istioctl analyze` | the configuration set is coherent |

Each can be right while another is wrong. A `200` with analyzer errors means you are getting lucky on a path that does not touch the broken object. A clean analyzer run with a `503` means the configuration is coherent but has not reached the proxy.

### See the chain, now whole

Read the route, run the analyzer, and read the client proxy's last log line:

```sh
istioctl proxy-config routes deploy/tester -n fivezerothree-demo -o json \
  | grep '"cluster"' | grep notification
istioctl analyze -n fivezerothree-demo
kubectl -n fivezerothree-demo logs deploy/tester -c istio-proxy --tail=1
```

You should see something like:

```text
        "cluster": "outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local",
✔ No validation issues found when analyzing namespace: fivezerothree-demo.
[...] "POST /notify HTTP/1.1" 200 - via_upstream - ... "10.244.0.12:8084" outbound|80|v1|notification-service... 
```

Three confirmations. The access log line closes the loop most precisely: the flag is `-` where it was `NC`, and there is an **upstream host address** where there was a `-`. That address proves a connection actually happened, in the same field that showed none had before.

## The method, for any 503

Everything in this module comes down to five steps that work for any `503`:

```text
   1. Read the response flag on the CLIENT proxy.          who failed it, and at which layer
   2. Check the DESTINATION proxy's log.                   did it arrive at all
   3. Run istioctl analyze.                                is there a named configuration fault
   4. Walk route → cluster → endpoint if not.              find the missing link
   5. Fix the end that matches reality, verify three ways. behaviour, configuration, coherence
```

Steps 1 and 2 cost one command each and remove most of the search space. Step 5's discipline, one change and then check again, is what makes the fix provable rather than lucky.

## Common pitfalls

> [!WARNING]
> - **Adding the missing subset by reflex.** A subset whose labels match no pod turns an `NC` into a `UH`: the analyzer goes quiet, the traffic still fails, and the diagnosis gets harder.
> - **Fixing several things in one apply.** When the symptom clears, you will not know which change mattered, and a fix you cannot explain is not a fix.
> - **Stopping at a `200`.** Confirm the proxy's route table and the analyzer too; either can disagree with a lucky request.
> - **Restarting pods after a routing change.** Routing is pushed over xDS. If it has not landed, the problem is delivery, not the pod.
> - **Assuming the fix belongs in Istio.** A `503` with flag `-` came from your app. Nothing in this method applies to it.

> *Resolve a dangling reference in the direction reality points. Inventing the target just trades a clear failure for a murky one.*

## Your mission: Trace A 503 To Its Exact Stage

You can now trace a `503` from its response flag to the missing link, and fix the end that matches reality. Now prove it in a graded mission: every request to `notification-service` fails, and you have to find the exact stage and repair it without inventing a subset.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-040-02
```

Then start the mission:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/module-02/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-040/module-02/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-016-lab-040-02
astrona start ats-016-playground-040-02
```
