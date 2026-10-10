# Solution: Trace A 503 To Its Exact Stage

This walkthrough asks who answered first, then walks the chain on the client proxy, fixes the end that matches reality, and proves the fix three ways.

## Step 1: Ask who answered, before asking why

Read the last lines of the `tester` pod's proxy log:

```sh
kubectl -n fivezerothree-demo logs deploy/tester -c istio-proxy --tail=5
```

```text
[...] "POST /notify HTTP/1.1" 503 NC cluster_not_found - "-" ... "notification-service" "-" ...
```

The line is shortened. Read the field after the status code. `NC` (no cluster found) means the **proxy** produced this `503`, not the application, and it names the reason: the route pointed at a cluster that does not exist. The next field, `cluster_not_found`, is Envoy's response code details: the same reason in words.

Two more details on that line:

- The upstream host field is `-`, so no connection was ever attempted.
- A flag of `-` would have meant the application answered, and this whole investigation would belong somewhere else.

Now check the **destination's** log for the same request:

```sh
kubectl -n fivezerothree-demo logs deploy/notification-service-v1 -c istio-proxy --tail=5
```

There is no matching line. The client failed and the server saw nothing, so the request never crossed the network, and the whole investigation stays on the sending side.

## Step 2: The fast path

Run the analyzer on the namespace:

```sh
istioctl analyze -n fivezerothree-demo
```

```text
Error [IST0101] (VirtualService fivezerothree-demo/notification) Referenced host+subset in destinationrule not found: "notification-service+v2"
```

That is often the whole answer. Walk the chain anyway: it is the skill that still works when no analyzer covers the case.

## Step 3: Walk route, cluster, endpoint

**Which cluster does the route name?**

```sh
istioctl proxy-config routes deploy/tester -n fivezerothree-demo -o json \
  | grep '"cluster"' | grep notification
```

```text
"cluster": "outbound|80|v2|notification-service.fivezerothree-demo.svc.cluster.local",
```

The four fields are outbound, port 80, subset **`v2`**, and the fully qualified name. The route stage worked: it produced a destination. The subset name is the first thing that is provably wrong.

**Does that cluster exist?**

```sh
istioctl proxy-config cluster deploy/tester -n fivezerothree-demo | grep notification
```

```text
notification-service....  80  -   outbound  EDS  notification.fivezerothree-demo
notification-service....  80  v1  outbound  EDS  notification.fivezerothree-demo
```

There are clusters for no subset and for `v1`, and no `v2` row. That confirms the flag from the configuration side.

**And the endpoints, for contrast:**

```sh
istioctl proxy-config endpoints deploy/tester -n fivezerothree-demo \
  --cluster "outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local"
```

```text
10.244.0.12:8084   HEALTHY   OK   outbound|80|v1|notification-service...
```

A healthy pod has been waiting in the `v1` cluster the whole time.

## Step 4: Fix the end that matches reality

Check which versions are really deployed:

```sh
kubectl -n fivezerothree-demo get pods --show-labels | grep notification
```

Only `version=v1` pods exist. So the route is wrong, not the `DestinationRule`. Save this as `virtualservice-notification.yaml`:

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

You can send it for grading now to see where you stand:

```sh
astrona submit
```

## Step 5: Verify three ways

Send ten requests, read the route again, run the analyzer, and read the client proxy's last log line:

```sh
kubectl -n fivezerothree-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -X POST http://notification-service/notify; done; echo'
istioctl proxy-config routes deploy/tester -n fivezerothree-demo -o json | grep '"cluster"' | grep notification
istioctl analyze -n fivezerothree-demo
sleep 2
kubectl -n fivezerothree-demo logs deploy/tester -c istio-proxy --tail=1
```

```text
200 200 200 200 200 200 200 200 200 200
"cluster": "outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local",
✔ No validation issues found when analyzing namespace: fivezerothree-demo.
[...] "POST /notify HTTP/1.1" 200 - via_upstream - ... "10.244.0.12:8084" outbound|80|v1|... 
```

The access log closes the loop most precisely: the flag is `-` where it was `NC`, and there is an upstream **address** where there was a `-`. Send the final answer for grading:

```sh
astrona submit
```

## Why adding a v2 subset is the wrong fix

```text
before:  route → v2, no v2 cluster            →  503, flag NC   "does not exist"
after:   route → v2, v2 cluster with no pods  →  503, flag UH   "nothing behind it"
```

The analyzer goes quiet and the traffic still fails, and the diagnosis is now harder, because `UH` has four possible causes instead of one. The task's constraint exists to reject exactly this, and the grader checks that every subset selects at least one running pod.

## Common mistakes

- **Reading the app log.** The proxy produced this `503`, so the app never saw the request.
- **Assuming the destination pod is broken.** Check the cluster and endpoints before restarting anything.
- **Overlooking the Service port protocol.** A port declared as TCP (for example named `tcp`) gets no HTTP routing at all, so every `VirtualService` rule for it is ignored.
- **Adding the subset to the wrong `DestinationRule`** when several exist for related hosts.

## Practice variations

- Rename the Service port from `http` to `tcp` and see that the `VirtualService` no longer applies at all.
- Delete the `DestinationRule` entirely and compare the response flag.
- Scale the Deployment to zero and watch `UH` appear instead of `NC`.
