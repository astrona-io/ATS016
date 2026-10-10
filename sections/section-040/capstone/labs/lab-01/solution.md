# Solution: Two 503s, Two Different Stages

This walkthrough reads the response flags first, then follows each service's failure to its own stage: the cluster stage for `notification-service`, the listener stage for `reporting-service`. It ends by proving both fixes.

## Step 1: Read the flags before forming a theory

Send one request to each service, then read the `tester` pod's proxy log:

```sh
kubectl -n dpcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null -X POST http://notification-service/notify
kubectl -n dpcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null http://reporting-service/status
kubectl -n dpcapstone-demo logs deploy/tester -c istio-proxy --tail=6
```

The two lines look nothing alike. The `notification-service` request carries a `503` with `NC` (no cluster found) and a `-` in the upstream host field: nothing was ever contacted. The `reporting-service` request has no HTTP request line at all, because the proxy handled it as a plain TCP connection with no HTTP routing.

That difference is the whole capstone: two failures, two stages.

## Step 2: notification-service, the cluster stage

Follow the chain, carrying each name to the next command:

```sh
istioctl proxy-config routes deploy/tester -n dpcapstone-demo -o json \
  | grep '"cluster"' | grep notification
istioctl proxy-config cluster deploy/tester -n dpcapstone-demo | grep notification
```

```text
"cluster": "outbound|80|canary|notification-service.dpcapstone-demo.svc.cluster.local",

notification-service....  80  -   outbound  EDS  notification.dpcapstone-demo
notification-service....  80  v1  outbound  EDS  notification.dpcapstone-demo
```

The route names subset `canary`; the proxy has clusters only for no subset and for `v1`. The route stage worked, because it produced a destination, but the cluster stage has nothing to resolve it to.

Check reality before you choose which end to fix:

```sh
kubectl -n dpcapstone-demo get pods --show-labels | grep notification
```

Only `version=v1` exists, so the route is wrong, not the `DestinationRule`. Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: dpcapstone-demo
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

Adding a `canary` subset whose labels match no pod would have satisfied the analyzer and turned `NC` into `UH`: a quieter failure with four possible causes instead of one.

## Step 3: reporting-service, the listener stage

The `VirtualService` for this host looks perfect and does nothing. Start at stage one:

```sh
istioctl proxy-config listener deploy/tester -n dpcapstone-demo --port 80
```

Find the line for `reporting-service`. Its `DESTINATION` is `Cluster: outbound|80||reporting-service.dpcapstone-demo.svc.cluster.local`, not a `Route:`. Compare that with an HTTP port, which matches `Trans: raw_buffer; App: http/1.1,h2c` and hands off to a **`Route:`**. Here the listener goes **straight to a cluster**. There is no route stage at all, so there is nothing for a `VirtualService` to attach to.

Find out why by reading the Service's ports:

```sh
kubectl -n dpcapstone-demo get svc reporting-service -o jsonpath='{.spec.ports}{"\n"}'
```

```text
[{"name":"tcp-web","port":80,"protocol":"TCP","targetPort":8080}]
```

Istio reads a port's protocol from `appProtocol` first, then from the port's **name** in the form `<protocol>[-<suffix>]` (`http`, `http2`, `grpc`, `tcp`, `tls` and so on). The port is named `tcp-web`, so its protocol is `tcp`, and Istio handles it as an opaque TCP stream. The `"protocol":"TCP"` field is the Kubernetes transport protocol, which every HTTP port has too; it is not the problem:

```text
port declared as tcp
     ├── no HTTP route is built            → the VirtualService never applies
     ├── no HTTP filters                   → retries, timeouts, header routing gone
     ├── no HTTP telemetry                 → absent from dashboards
     └── requests may still succeed        → which is why nobody noticed
```

`istioctl x describe pod` prints each Service port with the protocol Istio uses for it, which is another fast way to find it:

```sh
export POD=$(kubectl -n dpcapstone-demo get pod -l app=reporting-service -o jsonpath='{.items[0].metadata.name}')
istioctl x describe pod $POD -n dpcapstone-demo | tail -5
```

Fix the declaration, not the port:

```sh
kubectl -n dpcapstone-demo patch svc reporting-service --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/name","value":"http"}]'
```

No restart is needed: `istiod` regenerates the proxy's listeners over xDS within a second or two. You can send it for grading now to see where you stand:

```sh
astrona submit
```

## Step 4: Verify both, at both levels

Send one request to each service, read the port-80 listener again, and run the analyzer:

```sh
kubectl -n dpcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'notification %{http_code}\n' -X POST http://notification-service/notify
kubectl -n dpcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'reporting    %{http_code}\n' http://reporting-service/status
istioctl proxy-config listener deploy/tester -n dpcapstone-demo --port 80
istioctl analyze -n dpcapstone-demo
```

```text
notification 200
reporting    200
0.0.0.0  80  Trans: raw_buffer; App: http/1.1,h2c   Route: 80
✔ No validation issues found when analyzing namespace: dpcapstone-demo.
```

The listener now hands off to `Route: 80`, which proves that HTTP routing exists for that port at all. A `200` alone would not have shown it, because plain TCP passthrough also returns `200`. Send the final answer for grading:

```sh
astrona submit
```

## The two failures side by side

| | `notification-service` | `reporting-service` |
| --- | --- | --- |
| Stage | **cluster** | **listener** |
| Flag | `503` / `NC` | none: traffic succeeded, unrouted |
| Symptom | every request fails | rules silently ignored |
| Evidence | route names a cluster that does not exist | listener has no `Route:`, only a `Cluster:` |
| Fix | route to a subset that exists | declare the Service port as HTTP |
| Restart needed | no | no |

## Common mistakes

- **Reading the app log.** Both failures happened in a proxy.
- **Assuming the destination pod is broken.** Check the cluster and endpoints before restarting anything.
- **Rewriting a `VirtualService` that is never consulted.** When a rule is *ignored* rather than *wrong*, suspect the listener stage.
- **Overlooking the Service port declaration.** A port declared as `tcp` silently removes every HTTP rule for that Service.
- **Adding the missing subset to make the analyzer quiet.**

## Practice variations

- Rename the port back to `tcp-web` and watch which of the two symptoms returns. Then try `web` and explain why Istio's automatic protocol detection makes the routing work again.
- Set `appProtocol: http` instead of renaming the port, and confirm the listener changes the same way.
- Scale `notification-service-v1` to zero and compare the flag with the one you started from.
