# Solution: Consolidate Three Claimants Into One Route Table

## Step 1 — Count the claimants before reading any of them

```sh
kubectl -n routing-demo get virtualservice \
  -o custom-columns='NAME:.metadata.name,HOSTS:.spec.hosts,GATEWAYS:.spec.gateways'
```

```text
NAME                       HOSTS                     GATEWAYS
notification               [notification-service]    <none>
notification-priority      [notification-service]    <none>
notification-experiment    [notification-service]    <none>
```

Three objects, one host, all on the mesh gateway (omitted `gateways:` means
`mesh`). Istio **merges** them into one virtual host and the resulting rule
order is not defined by anything you control.

```sh
istioctl analyze -n routing-demo
```

```text
Warning [IST0109] ... define the same host notification-service which can lead to undefined behavior.
```

A `Warning`, because nothing is invalid. `undefined behavior` is precise, not
dramatic: the configuration works, and its meaning can change when any one of
the three objects is edited.

## Step 2 — Ask the proxy what it is actually running

```sh
istioctl proxy-config routes deploy/tester -n routing-demo \
  --name 80 -o json | grep -E '"cluster"|"exact_match"|"prefix"' | head -20
```

Whatever order you see, it is not one anybody chose. Reading the three YAML
files could not have told you this — which is the lesson the capstone is built
around.

## Step 3 — Understand the second fault

```sh
kubectl -n routing-demo get virtualservice notification -o yaml | sed -n '/^ *http:/,$p'
```

Its catch-all sits at index 0 and its header rule at index 1. Envoy walks the
list top down and **the first match wins**; a rule with no `match` compiles to a
prefix match on `/`, which is true for every request. Everything below it is
unreachable — even if the merge happened to put this object first.

So there are two independent faults: three owners, and a shadowed rule inside
one of them. Fixing either alone leaves the behaviour undefined.

## Step 4 — Consolidate

Delete the extra claimants, then write one object with the specific matches
first and the unconditional route last:

```sh
kubectl -n routing-demo delete virtualservice notification-priority notification-experiment
cat > virtualservice-notification.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: routing-demo
spec:
  hosts:
    - notification-service
  http:
    - match:
        - headers:
            testing:
              exact: "true"
      route:
        - destination:
            host: notification-service
            subset: v2
    - match:
        - uri:
            prefix: /priority
      route:
        - destination:
            host: notification-service
            subset: v2
    - route:
        - destination:
            host: notification-service
            subset: v1
EOF
kubectl apply -f virtualservice-notification.yaml
```

Order matters between the two specific rules only if they could both match the
same request; here they cannot. What matters absolutely is that the
unconditional rule is **last**.

```sh
astrona submit
```

## Step 5 — Verify all three paths, with volume

```sh
kubectl -n routing-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST -H "testing: true" http://notification-service/notify; echo; done' | sort -u
kubectl -n routing-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/priority; echo; done' | sort -u
kubectl -n routing-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
```

```text
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL"]
```

One line per path. Ten requests rather than one: with two subsets behind one
Service, a single response proves nothing — and a second line from any path
would mean traffic is still being split.

```sh
istioctl analyze -n routing-demo
istioctl proxy-config routes deploy/tester -n routing-demo --name 80 -o json \
  | grep -E '"cluster"|"exact_match"|"/priority"' | head
astrona submit
```

## The legitimate way to have two objects

Two `VirtualService` objects claiming one host are only safe when their **gateway
scopes do not overlap** — for example one bound to an ingress `Gateway` for
external traffic and one bound to `mesh` for internal:

```text
notification-external   gateways: [public-gw]   → the ingress gateway's route table
notification-internal   gateways: [mesh]        → every sidecar's route table
```

For deliberate composition within one scope, Istio has `spec.http[].delegate`,
which is an explicit, ordered mechanism rather than an incidental merge.

## Common mistakes

- Adding another `VirtualService` to "override" the existing ones. That creates
  the conflict rather than resolving it.
- Reading only the YAML you wrote. The proxy route table is the only authority.
- Putting the catch-all route first. Everything under it is unreachable and
  nothing warns you at apply time.
- Assuming merge order is stable — it can change when an unrelated object is
  edited.
- Verifying one path out of three.

## Practice variations

- Split two of the objects by gateway binding so both can legitimately coexist.
- Add a fourth rule below the catch-all and confirm from the route table that it
  never appears.
- Re-introduce `notification-experiment`, then diff the proxy route table before
  and after.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
