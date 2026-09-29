# Solution: Trace A 503 To Its Exact Stage

## Step 1 — Ask who answered, before asking why

```sh
kubectl -n fivezerothree-demo logs deploy/tester -c istio-proxy --tail=5
```

```text
[...] "POST /notify HTTP/1.1" 503 NC no_healthy_upstream - "-" 0 19 0 - ... "notification-service" "-" ...
```

Read the fourth field. `NC` — no cluster — means the **proxy** produced this,
not the application, and names the reason: the route pointed at a cluster that
does not exist. (Depending on version and state you may see `UH` here instead;
read the flag you actually get.)

Two more details on that line:

- the upstream host field is `-`, so no connection was ever attempted;
- a flag of `-` would have meant the application answered, and this whole
  investigation would belong somewhere else.

Now check the **destination's** log for the same request:

```sh
kubectl -n fivezerothree-demo logs deploy/notification-service-v1 -c istio-proxy --tail=5
```

Nothing corresponding. Client failed, server saw nothing — the request never
crossed the network, so the entire investigation stays on the sending side.

## Step 2 — The fast path

```sh
istioctl analyze -n fivezerothree-demo
```

```text
Error [IST0101] (VirtualService notification.fivezerothree-demo) Referenced host+subset in destinationrule not found: "notification-service+v2"
```

Often the whole answer. Work the chain anyway — it is the skill that survives
the cases no analyzer covers.

## Step 3 — Walk route → cluster → endpoint

**Which cluster does the route name?**

```sh
istioctl proxy-config routes deploy/tester -n fivezerothree-demo -o json \
  | grep '"cluster"' | grep notification
```

```text
"cluster": "outbound|80|v2|notification-service.fivezerothree-demo.svc.cluster.local",
```

Four fields: outbound, port 80, subset **`v2`**, that FQDN. The route stage
worked — it produced a destination. The subset name is the first thing that is
verifiably wrong.

**Does that cluster exist?**

```sh
istioctl proxy-config cluster deploy/tester -n fivezerothree-demo | grep notification
```

```text
notification-service....  80  -   outbound  EDS  notification.fivezerothree-demo
notification-service....  80  v1  outbound  EDS  notification.fivezerothree-demo
```

The subsetless cluster and `v1`. No `v2` row. Confirmed from the configuration
side, independently of the flag.

**And the endpoints, for the contrast:**

```sh
istioctl proxy-config endpoints deploy/tester -n fivezerothree-demo \
  --cluster "outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local"
```

```text
10.244.0.12:8084   HEALTHY   OK   outbound|80|v1|notification-service...
```

A healthy pod has been waiting there the whole time.

## Step 4 — Fix the end that matches reality

```sh
kubectl -n fivezerothree-demo get pods --show-labels | grep notification
```

Only `version=v1` pods exist. So the route is wrong, not the `DestinationRule`:

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > virtualservice-notification.yaml <<'EOF'
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
EOF
kubectl apply -f virtualservice-notification.yaml
```

```sh
astrona submit
```

## Step 5 — Verify three ways

```sh
kubectl -n fivezerothree-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -X POST http://notification-service/notify; done; echo'
istioctl proxy-config routes deploy/tester -n fivezerothree-demo -o json | grep '"cluster"' | grep notification
istioctl analyze -n fivezerothree-demo
kubectl -n fivezerothree-demo logs deploy/tester -c istio-proxy --tail=1
```

```text
200 200 200 200 200 200 200 200 200 200
"cluster": "outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local",
✔ No validation issues found when analyzing namespace: fivezerothree-demo.
[...] "POST /notify HTTP/1.1" 200 - via_upstream - ... "10.244.0.12:8084" outbound|80|v1|... 
```

The access log closes the loop most precisely: flag `-` where it was `NC`, and
an upstream **address** where there was a `-`.

```sh
astrona submit
```

## Why adding a v2 subset is the wrong fix

```text
before:  route → v2, no v2 cluster            →  503, flag NC   "does not exist"
after:   route → v2, v2 cluster with no pods  →  503, flag UH   "nothing behind it"
```

The analyzer goes quiet and the traffic still fails — and the diagnosis is now
harder, because `UH` has four possible causes instead of one. The task's
constraint exists to reject exactly this.

## Common mistakes

- Reading the application log. The proxy generated this `503`, so the
  application never saw the request.
- Assuming the destination pod is broken. Check the cluster and endpoints before
  restarting anything.
- Overlooking the Service port name. An unnamed or wrongly named port breaks
  HTTP routing with the same symptom.
- Adding the subset to the wrong `DestinationRule` when several exist for
  related hosts.

## Practice variations

- Rename the Service port from `http` to `foo` and reproduce a `503` with a
  different cause.
- Delete the `DestinationRule` entirely and compare the response flag.
- Scale the Deployment to zero and observe `UH` instead of `NC`.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Envoy access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — turning logging on and reading the response flags
- [Common problems: network issues](https://istio.io/latest/docs/ops/common-problems/) — the catalogue of 503 causes and how to tell them apart
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
