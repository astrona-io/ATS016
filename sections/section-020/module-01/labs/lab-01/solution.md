# Solution: Make The Header Route Actually Fire

## Step 1 — Characterise the failure

```sh
kubectl -n conflict-demo exec deploy/tester -- sh -c \
  'curl -s -X POST -H "testing: true" http://notification-service/notify; echo'
kubectl -n conflict-demo exec deploy/tester -- sh -c \
  'curl -s -X POST http://notification-service/notify; echo'
```

Both return `["EMAIL"]`. The header made **no** difference at all — and that
totality is the clue. A rule that partly works points at a matching bug; a rule
with no effect whatsoever points at a rule that was never consulted.

## Step 2 — Cause one: host ownership

```sh
kubectl -n conflict-demo get virtualservice \
  -o custom-columns='NAME:.metadata.name,HOSTS:.spec.hosts,GATEWAYS:.spec.gateways'
```

```text
NAME                  HOSTS                     GATEWAYS
notification          [notification-service]    <none>
notification-extra    [notification-service]    <none>
```

Two objects, one host, both on the mesh gateway. Istio **merges** them into one
virtual host and the resulting rule order is not defined by anything you
control. The analyzer says so:

```sh
istioctl analyze -n conflict-demo
```

```text
Warning [IST0109] ... define the same host notification-service which can lead to undefined behavior.
```

A `Warning`, not an `Error` — nothing here is invalid, which is why it survived.

## Step 3 — Cause two: a shadowed rule

```sh
kubectl -n conflict-demo get virtualservice notification -o yaml | sed -n '/^spec:/,$p'
```

The catch-all route sits at index 0 and the header rule at index 1. Envoy walks
`http:` top down and **the first match wins**; a rule with no `match` block
compiles to a prefix match on `/`, which is true for every request. Everything
below it is unreachable.

## Step 4 — Confirm from the proxy before changing anything

```sh
istioctl proxy-config routes deploy/tester -n conflict-demo \
  --name 80 -o json | grep -E '"cluster"|"exact_match"' | head
```

Only `v1` clusters appear, and no header match anywhere. The route to `v2` does
not exist as far as this proxy is concerned — which is the decisive evidence,
and the reason the YAML alone could not tell you.

## Step 5 — Fix both causes

Delete the duplicate claimant, then reorder the survivor: **specific match
first, unconditional last.**

```sh
kubectl -n conflict-demo delete virtualservice notification-extra
cat > virtualservice-notification.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: conflict-demo
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
    - route:
        - destination:
            host: notification-service
            subset: v1
EOF
kubectl apply -f virtualservice-notification.yaml
```

No pod restarts: a `VirtualService` edit is an RDS push over the existing xDS
stream and the proxy swaps its route table in place.

```sh
astrona submit
```

## Step 6 — Verify both paths, with volume

```sh
kubectl -n conflict-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST -H "testing: true" http://notification-service/notify; echo; done' | sort -u
kubectl -n conflict-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
```

```text
["EMAIL","SMS"]
["EMAIL"]
```

One line per path. Two lines from one path would mean traffic is still being
split — the failure mode a single request cannot detect.

```sh
astrona submit
```

## Why the shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Add a third `VirtualService` to "override" the others | that creates the conflict rather than resolving it |
| Reorder the rules but keep both objects | the merge can reshuffle them again when either is edited |
| Delete `notification` instead of `notification-extra` | you keep the object with no header rule at all |
| Bind one object to a gateway to "separate" them | legitimate in general, but the task requires mesh traffic to have one owner |

## Common mistakes

- Reading only the YAML you wrote. The proxy route table is the only authority
  on what is in effect.
- Putting the catch-all route first. Every rule under it is unreachable and
  nothing warns you at apply time.
- Assuming merge order is stable — it can change when an unrelated object is
  edited.
- Verifying one path. Fixing the header route by making the default unreachable
  is not a fix.

## Practice variations

- Split the two objects by binding one to a gateway and one to `mesh`, so both
  can legitimately coexist.
- Add a third rule matching `uri: prefix: /priority` and predict its position in
  the proxy before checking.
- Deliberately place the default route first again and watch the route table.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
