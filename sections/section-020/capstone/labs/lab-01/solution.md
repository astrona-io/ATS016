# Solution: Consolidate Three Claimants Into One Route Table

This capstone has two separate faults: three owners for one host, and a shadowed rule inside one of them. This walkthrough counts the owners, asks the proxy what it really runs, combines every rule into one object in the right order, and checks all three paths. The grader checks four things: one owner with no `IST0109`, the header path on `v2`, the `/priority` path on `v2`, and every other request on `v1`.

## Step 1: Count the owners before reading any of them

List every `VirtualService` with its hosts and gateways:

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

Three objects, one host, all on the mesh gateway (an omitted `gateways:` field means `mesh`). Host merging is not supported in sidecars: the sidecar proxy (Envoy) uses the rules of only one of the three objects for this host and drops the other two. Nothing in your YAML decides which one wins.

Run the analyzer:

```sh
istioctl analyze -n routing-demo
```

```text
Error [IST0109] ... define the same host notification-service which can lead to undefined behavior.
```

The output above is shortened. `IST0109` is an `Error`, yet `kubectl apply` accepted all three objects, because the API server checks each object on its own. `undefined behavior` is exact: requests get answers, and which object is in use can change when any one of the three is deleted or recreated.

## Step 2: Ask the proxy what it is really running

Read the client proxy's route table for port 80:

```sh
istioctl proxy-config routes deploy/tester -n routing-demo \
  --name 80 -o json | grep -E '"cluster"|"exact_match"|"prefix"' | head -20
```

The clusters and matches you see belong to one object only, and nobody chose which one. Reading the three YAML files could not have told you this, and that is the lesson this capstone is built around.

## Step 3: Understand the second fault

Print the rules of the `notification` object:

```sh
kubectl -n routing-demo get virtualservice notification -o yaml | sed -n '/^ *http:/,$p'
```

Its catch-all sits at index 0 and its header rule at index 1. The proxy walks the list from the top and **the first match wins**. A rule with no `match` becomes a prefix match on `/`, which is true for every request, so every rule below it is shadowed and never reached, even when the proxy uses this object.

So there are two separate faults: three owners, and a shadowed rule inside one of them. Fixing either one alone leaves the behaviour undefined.

## Step 4: Combine the rules into one object

Delete the extra objects:

```sh
kubectl -n routing-demo delete virtualservice notification-priority notification-experiment
```

Then write one object with the specific matches first and the unconditional route last.

Save this as `virtualservice-notification.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

The order of the two specific rules matters only if both could match the same request, and here they cannot. What matters absolutely is that the unconditional rule is **last**.

## Step 5: Check all three paths, ten requests each

Send ten requests down each path:

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

One line per path. With two subsets behind one Service, a single answer proves nothing, and a second line from any path would mean traffic is still being split.

Then confirm the analyzer is clean and the route table holds your order:

```sh
istioctl analyze -n routing-demo
istioctl proxy-config routes deploy/tester -n routing-demo --name 80 -o json \
  | grep -E '"cluster"|"exact_match"|"/priority"' | head
```

## Step 6: Submit

Send the capstone for grading:

```sh
astrona submit
```

All four checks should pass. If one fails, its message names the path that is still wrong, or the number of objects that still claim the host.

## The legitimate way to have two objects

Two `VirtualService` objects that claim one host are only safe when their **gateway scopes do not overlap**. For example, one is bound to an ingress `Gateway` for traffic from outside and one is bound to `mesh` for traffic inside:

```text
notification-external   gateways: [public-gw]   → the ingress gateway's route table
notification-internal   gateways: [mesh]        → every sidecar's route table
```

For a planned split within one scope, Istio has `spec.http[].delegate`: a root `VirtualService` hands named parts of its routing to other objects, in an explicit order.

## Common mistakes

- Adding another `VirtualService` to "override" the existing ones. The proxy still uses only one object for the host, and you cannot say which.
- Reading only the YAML you wrote. The proxy's route table is the only record of what is in force.
- Putting the catch-all route first. Everything under it can never be reached. The apply still succeeds and only prints a `Warning` line that is easy to miss.
- Assuming the winning object stays the same. It can change when any of the objects is deleted or recreated.
- Checking one path out of three.

## Practice variations

- Split two of the objects by gateway binding so both can live together legitimately.
- Add a fourth rule below the catch-all and confirm from the route table that it never appears.
- Bring `notification-experiment` back, then compare the proxy's route table before and after.
