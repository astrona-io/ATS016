# Solution: Make The Header Route Actually Fire

The header route fails for two separate reasons, and neither one produces an error. This walkthrough finds each cause, proves it from the proxy, fixes both, and checks both paths with real traffic. The grader checks three things: one owner for the host with no `IST0109`, every header request reaching `v2`, and every plain request reaching `v1`.

## Step 1: Describe the failure

Send one request with the header and one without, from the `tester` pod:

```sh
kubectl -n conflict-demo exec deploy/tester -- sh -c \
  'curl -s -X POST -H "testing: true" http://notification-service/notify; echo'
kubectl -n conflict-demo exec deploy/tester -- sh -c \
  'curl -s -X POST http://notification-service/notify; echo'
```

Both return `["EMAIL"]`. The header made **no** difference at all, and that is the clue. A rule that partly works points at a matching bug. A rule with no effect at all points at a rule that was never checked.

## Step 2: Find cause one, two owners for one host

List every `VirtualService` with its hosts and gateways:

```sh
kubectl -n conflict-demo get virtualservice \
  -o custom-columns='NAME:.metadata.name,HOSTS:.spec.hosts,GATEWAYS:.spec.gateways'
```

```text
NAME                  HOSTS                     GATEWAYS
notification          [notification-service]    <none>
notification-extra    [notification-service]    <none>
```

Two objects, one host, both on the mesh gateway. Istio **merges** them into one virtual host, and nothing you control decides the order of the merged rules. The analyzer says so:

```sh
istioctl analyze -n conflict-demo
```

```text
Warning [IST0109] ... define the same host notification-service which can lead to undefined behavior.
```

The output above is shortened. It is a `Warning`, not an `Error`: nothing here is invalid, which is why it survived.

## Step 3: Find cause two, a shadowed rule

Print the `spec` of the `notification` object:

```sh
kubectl -n conflict-demo get virtualservice notification -o yaml | sed -n '/^spec:/,$p'
```

The catch-all route sits at index 0 and the header rule at index 1. The proxy walks `http:` from the top and **the first match wins**. A rule with no `match` block becomes a prefix match on `/`, which is true for every request, so everything below it can never be reached.

## Step 4: Confirm from the proxy before you change anything

Ask the client's proxy what it really holds for port 80:

```sh
istioctl proxy-config routes deploy/tester -n conflict-demo \
  --name 80 -o json | grep -E '"cluster"|"exact_match"' | head
```

Only `v1` clusters appear, and there is no header match anywhere. As far as this proxy is concerned, the route to `v2` does not exist. That is the decisive evidence, and the reason the YAML alone could not tell you.

## Step 5: Fix both causes

First delete the duplicate claimant, so one object owns the host:

```sh
kubectl -n conflict-demo delete virtualservice notification-extra
```

Then reorder the object that is left: **specific match first, unconditional last.**

Save this as `virtualservice-notification.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

No pod restarts. `istiod` sends the new routes to the proxy over the connection it already has, and the proxy swaps its route table in place.

## Step 6: Check both paths, ten requests each

Send ten requests with the header and ten without:

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

One line per path. Two lines from one path would mean traffic is still being split, which a single request cannot show.

## Step 7: Submit

Send the lab for grading:

```sh
astrona submit
```

All three checks should pass: one owner for the host with no `IST0109`, the header path on `v2`, and the default path on `v1`. If one fails, its message names the path that is still wrong.

## Why the shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Add a third `VirtualService` to "override" the others | that makes the conflict worse instead of solving it |
| Reorder the rules but keep both objects | the merge can reshuffle them again when either is edited |
| Delete `notification` instead of `notification-extra` | you keep the object with no header rule at all |
| Bind one object to a gateway to "separate" them | fine in general, but the task needs mesh traffic to have one owner |

## Common mistakes

- Reading only the YAML you wrote. The proxy's route table is the only record of what is in force.
- Putting the catch-all route first. Every rule under it can never be reached, and nothing warns you when you apply it.
- Assuming the merge order stays the same. It can change when an unrelated object is edited.
- Checking one path. Fixing the header route by making the default unreachable is not a fix.

## Practice variations

- Split the two objects by binding one to a gateway and one to `mesh`, so both can live together legitimately.
- Add a third rule matching `uri: prefix: /priority` and predict its position in the proxy before you check.
- Put the default route first again on purpose and watch the route table.
