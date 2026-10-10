# Choosing And Proving The Fix

A reference that does not resolve can always be fixed from either end: create the target, or stop pointing at it. Only one of those is right in a given case. Choose wrong, and you get a configuration that satisfies the analyzer while the requests still fail. This part makes the choice explicit, applies the fix, and proves it three ways.

## Two fixes, one correct

The `VirtualService` names `subset: v2`, and the `DestinationRule` defines only `v1`. Two different edits would make the reference resolve. The first is to change the `VirtualService` to `subset: v1`. This is right when the `v2` reference was a mistake, which is the usual case: a manifest copied from an environment where `v2` was deployed, a version rolled back without updating the routing, or a subset renamed on one side only.

The second is to add `v2` to the `DestinationRule`. This is right **only if pods with the label `version: v2` actually exist**. Here they do not, because the namespace runs one Deployment with the label `version: v1`. Adding the subset anyway looks like progress, which is what makes it dangerous:

```text
   before:   route → v2,  no v2 cluster          →  503, flag NC
                                                     "the cluster does not exist"

   add a v2 subset whose labels match no pod:

   after:    route → v2,  v2 cluster exists      →  503, flag UH
             cluster has NO endpoints                "no healthy upstream host"
```

The analyzer goes quiet, because `IST0101` is satisfied once the reference resolves. The requests still fail. And the diagnosis is now *harder*, because the clear "this does not exist" has turned into the vaguer "there is nothing behind it". An empty cluster has four possible causes (Service selector, readiness, subset labels, removed endpoints) instead of one.

The rule is: **make the reference true in the direction that matches what is deployed.** Check what is running before you create a target for it. List the application's pods with their labels:

<!-- astrona:playground:renew -->

```sh
kubectl -n fivezerothree-demo get pods --show-labels | grep notification
```

Only pods with `version=v1` exist. That one command decides the fix: the route is wrong, not the `DestinationRule`.

## Applying it

Rewrite the `VirtualService` so it routes to the subset that exists.

Save this as `virtualservice-notification.yaml`:

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

Then check the result with one request from the `tester` pod:

```sh
kubectl -n fivezerothree-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

```text
200
```

The fix took effect within a second or two, and no pod restarted. `istiod` turned the `VirtualService` change into a new route configuration and pushed it to the proxy over xDS, the protocol `istiod` uses to send configuration to proxies while they run. The proxy replaced its route table in place. If a routing change ever *does* seem to need a restart, the problem is delivery, and `istioctl proxy-status` is the next command, not `kubectl rollout restart`.

## Proving it three ways

A `200` is good evidence, but not complete evidence. Three sources were wrong at the start, and all three should now agree:

| Source | Proves |
| --- | --- |
| a real request | the behaviour is right **now** |
| the proxy's route table | the proxy holds what you think it holds |
| `istioctl analyze` | the configuration set is coherent |

Each can be right while another is wrong. A `200` with analyzer errors means the request took a path that does not touch the broken object. A clean analyzer run with a `503` means the configuration is coherent but has not reached the proxy. Read the route, run the analyzer, and read the client proxy's last log line:

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
[2026-10-09T22:24:00.586Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 9 6 5 "-" "curl/8.22.0" "95de549a-9e12-92c4-a50f-c3a9a0844e4d" "notification-service" "10.244.0.8:8084" outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local 10.244.0.9:46392 10.96.187.226:80 10.244.0.9:56716 - -
```

All three agree. The access log line is the most precise proof: the flag is `-` where it was `NC`, and there is an **upstream host address** where there was a `-`. That address proves a connection to a pod actually happened, in the same field that showed none had before.

## The method, for any 503

Everything in this module comes down to five steps that work for any `503`:

1. Read the response flag on the **client** proxy: who failed the request, and at which stage.
2. Check the **destination** proxy's log: did the request arrive at all.
3. Run `istioctl analyze`: is there a named configuration fault.
4. If not, walk route, cluster and endpoint to find the missing link.
5. Fix the end that matches what is deployed, then verify three ways.

Steps 1 and 2 cost one command each and remove most of the search space. Step 5, one change and then check again, is what makes the fix provable rather than lucky.

You can now choose the correct end of a broken reference, apply the fix, and prove it with a request, the proxy's route table and the analyzer. The case in this part had a clear signature: a `503` with `NC`. The next part covers a cause with a quieter signature, where routing rules are ignored rather than wrong.

## Common pitfalls

> [!WARNING]
> - **Adding the missing subset by reflex.** A subset whose labels match no pod turns an `NC` into a `UH`: the analyzer goes quiet, requests still fail, and the diagnosis gets harder.
> - **Fixing several things in one apply.** When the symptom clears, you will not know which change mattered.
> - **Stopping at a `200`.** Confirm the proxy's route table and the analyzer too; either can disagree with a lucky request.
> - **Restarting pods after a routing change.** Routing is pushed over xDS. If it has not arrived, the problem is delivery, not the pod.
> - **Assuming the fix belongs in Istio.** A `503` with the flag `-` came from your application. Nothing in this method applies to it.

## Your mission: Trace A 503 To Its Exact Stage

You can now trace a `503` from its response flag to the missing link, and fix the end that matches what is deployed. The graded lab gives you a namespace where every request to `notification-service` fails, and asks you to find the exact stage and repair it without creating a subset that matches no pod.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-040-02
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/module-02/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-040/module-02/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-040-02
astrona start ats-016-playground-040-02
```
