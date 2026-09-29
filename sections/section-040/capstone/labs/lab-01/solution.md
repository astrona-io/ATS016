# Solution: Two 503s, Two Different Stages

## Step 1 — Read the flags before forming a theory

```sh
kubectl -n dpcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null -X POST http://notification-service/notify
kubectl -n dpcapstone-demo exec deploy/tester -- \
  curl -s -o /dev/null http://reporting-service/status
kubectl -n dpcapstone-demo logs deploy/tester -c istio-proxy --tail=6
```

The two lines look nothing alike. The `notification-service` request carries a
`503` with `NC` (no cluster) and a `-` in the upstream host field — nothing was
ever contacted. The `reporting-service` request went somewhere, on a plain TCP
connection, with no HTTP routing applied at all.

That difference is the whole capstone: two failures, two stages.

## Step 2 — notification-service: the cluster stage

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

The route names subset `canary`; the proxy has clusters for the subsetless case
and `v1` only. The route stage worked — it produced a destination — and the
cluster stage has nothing to resolve it to.

Check reality before choosing which end to fix:

```sh
kubectl -n dpcapstone-demo get pods --show-labels | grep notification
```

Only `version=v1` exists, so the route is wrong, not the `DestinationRule`:

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > virtualservice-notification.yaml <<'EOF'
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
EOF
kubectl apply -f virtualservice-notification.yaml
```

Adding a `canary` subset whose labels match no pod would have satisfied the
analyzer and converted `NC` into `UH` — a quieter failure with four possible
causes instead of one.

## Step 3 — reporting-service: the listener stage

The `VirtualService` for this host looks perfect and does nothing. Start at
stage one:

```sh
istioctl proxy-config listener deploy/tester -n dpcapstone-demo --port 80
```

```text
ADDRESSES  PORT  MATCH   DESTINATION
0.0.0.0    80    ALL     Cluster: outbound|80||reporting-service.dpcapstone-demo.svc.cluster.local
```

Compare that with a healthy HTTP port, which reads
`Trans: raw_buffer; App: http/1.1,h2c` and hands off to a **`Route:`**. Here the
listener goes **straight to a cluster** — there is no route stage at all, so
there is nothing for a `VirtualService` to attach to.

Why:

```sh
kubectl -n dpcapstone-demo get svc reporting-service -o jsonpath='{.spec.ports}{"\n"}'
```

```text
[{"name":"web","port":80,"protocol":"TCP","targetPort":8080}]
```

Istio infers a port's protocol from its **name** (`http`, `http2`, `grpc`,
`tcp`, `tls`, … optionally suffixed as `http-status`) or from `appProtocol`. A
port named `web` declares nothing, so the traffic is treated as plain TCP:

```text
port has no declared protocol
     ├── no HTTP route is built            → the VirtualService never applies
     ├── no HTTP filters                   → retries, timeouts, header routing gone
     ├── no HTTP telemetry                 → absent from dashboards
     └── requests may still succeed        → which is why nobody noticed
```

`istioctl x describe pod` reports it as a warning, which is the fastest way to
find it:

```sh
export POD=$(kubectl -n dpcapstone-demo get pod -l app=reporting-service -o jsonpath='{.items[0].metadata.name}')
istioctl x describe pod $POD -n dpcapstone-demo | tail -5
```

Fix the declaration, not the port:

```sh
kubectl -n dpcapstone-demo patch svc reporting-service --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/name","value":"http"}]'
```

No restart is needed — the Service change re-generates the proxy's listeners
over xDS within a second or two.

```sh
astrona submit
```

## Step 4 — Verify both, at both levels

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

The listener now hands off to `Route: 80`, which is the proof that HTTP routing
exists for that port at all — a `200` alone would not have shown it, because
plain TCP passthrough also returns `200`.

```sh
astrona submit
```

## The two failures side by side

| | `notification-service` | `reporting-service` |
| --- | --- | --- |
| Stage | **cluster** | **listener** |
| Flag | `503` / `NC` | none — traffic succeeded, unrouted |
| Symptom | every request fails | rules silently ignored |
| Evidence | route names a cluster that does not exist | listener has no `Route:`, only a `Cluster:` |
| Fix | route to a subset that exists | name the Service port |
| Restart needed | no | no |

## Common mistakes

- Reading the application log. Both failures happened in a proxy.
- Assuming the destination pod is broken. Check the cluster and endpoints before
  restarting anything.
- Rewriting a `VirtualService` that is never consulted. When a rule is *ignored*
  rather than *wrong*, suspect the listener stage.
- Overlooking the Service port name. It is the single most common cause of
  "Istio is not applying my configuration".
- Adding the missing subset to make the analyzer quiet.

## Practice variations

- Rename the port back to `web` and watch which of the two symptoms returns.
- Set `appProtocol: http` instead of renaming the port, and confirm the listener
  changes the same way.
- Scale `notification-service-v1` to zero and compare the flag with the one you
  started from.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Describing pod configuration](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-describe/) — what the mesh is applying to one workload
- [Envoy access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — turning logging on and reading the response flags
- [Common problems: network issues](https://istio.io/latest/docs/ops/common-problems/) — the catalogue of 503 causes and how to tell them apart
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
