# Solution: Build The Routing, Then Prove It From The Proxy

This walkthrough builds the routing in two small objects, then proves it from the `tester` proxy's own configuration, one stage at a time. Each step ends with something you can see.

## Step 1: See the default behaviour first

Send ten requests from the test ship and list the different answers:

```sh
kubectl -n proxycfg-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
```

```text
["EMAIL"]
["EMAIL","SMS"]
```

There are two different answers: with no Istio configuration, the Service spreads requests across both versions. That is the starting point the routing will replace.

Now look at what the proxy already holds, before you add anything:

```sh
istioctl proxy-config cluster deploy/tester -n proxycfg-demo \
  --fqdn notification-service.proxycfg-demo.svc.cluster.local
```

```text
SERVICE FQDN                                            PORT  SUBSET  DIRECTION  TYPE  DESTINATION RULE
notification-service.proxycfg-demo.svc.cluster.local    80    -       outbound   EDS
```

There is one cluster, with an empty subset field and an empty `DESTINATION RULE` column. The cluster without a subset always exists for a known Service. Subset clusters exist only when a `DestinationRule` creates them.

## Step 2: Define the subsets

Save this as `destinationrule-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification
  namespace: proxycfg-demo
spec:
  host: notification-service
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
```

Apply it:

```sh
kubectl apply -f destinationrule-notification.yaml
```

Then check the result:

```sh
istioctl proxy-config cluster deploy/tester -n proxycfg-demo \
  --fqdn notification-service.proxycfg-demo.svc.cluster.local
```

Two more clusters now exist, one for `v1` and one for `v2`. Applying a `DestinationRule` alone changed no traffic: it created destinations, but it did not route anything to them.

## Step 3: Route to them

Put the specific match first and the rule with no condition last. Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: proxycfg-demo
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

Note that `exact: "true"` is **quoted**. Without quotes, YAML reads it as a true/false value, not the text the header carries, and the rule silently never matches.

You can already send it for grading to see where you stand:

```sh
astrona submit
```

## Step 4: Walk the four stages on the client proxy

This is the part the task really grades. Each stage hands a name to the next.

**Listener**: what catches the traffic.

```sh
istioctl proxy-config listener deploy/tester -n proxycfg-demo --port 80
```

```text
ADDRESSES  PORT  MATCH                                  DESTINATION
0.0.0.0    80    Trans: raw_buffer; App: http/1.1,h2c   Route: 80
0.0.0.0    80    ALL                                    PassthroughCluster
```

The HTTP chain hands off to `Route: 80`. The second entry is the fallback for traffic that is not HTTP.

**Route**: the table form hides match conditions, so use JSON.

```sh
istioctl proxy-config route deploy/tester -n proxycfg-demo --name 80 -o json \
  | grep -E '"exact_match"|"cluster"' | head
```

```text
"exact_match": "true",
"cluster": "outbound|80|v2|notification-service.proxycfg-demo.svc.cluster.local",
"cluster": "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local",
```

The header match is attached to `v2`, and `v1` follows as the catch-all, in the order you wrote them.

**Cluster**: read the four fields of each name, `direction|port|subset|fqdn`. Both subset clusters appeared in Step 2.

**Endpoint**: what the name resolves to right now. Quote the cluster name, because `|` is a shell pipe.

```sh
istioctl proxy-config endpoint deploy/tester -n proxycfg-demo \
  --cluster "outbound|80|v2|notification-service.proxycfg-demo.svc.cluster.local"
```

```text
ENDPOINT           STATUS    OUTLIER CHECK   CLUSTER
10.244.0.14:8084   HEALTHY   OK              outbound|80|v2|notification-service...
```

The endpoint is on the **container** port 8084, not the Service port 80. The proxy connects straight to the pod, so the Service port only ever appears in the cluster name. Run the same command with `v1` in the cluster name to check the other subset.

## Step 5: Confirm with traffic too

Send ten requests with the header and ten without:

```sh
kubectl -n proxycfg-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST -H "testing: true" http://notification-service/notify; echo; done' | sort -u
kubectl -n proxycfg-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
```

```text
["EMAIL","SMS"]
["EMAIL"]
```

Every request with the header reached `v2`, and every request without it reached `v1`. Send the final answer for grading:

```sh
astrona submit
```

## Common mistakes

- **Looking at the wrong proxy.** Outbound routing lives on the **client**; authorization and inbound listeners live on the **destination**.
- **Reading the short table output when the answer needs `-o json`.** Match conditions are only in the JSON.
- **Searching a full `proxy-config all` dump by eye.** Narrow with `--fqdn` and `--port` first.
- **Forgetting that ports 15001, 15006, 15021 and 15090 belong to Istio**, not to your app.
- **Writing `exact: true` without quotes.**

## Practice variations

- Save the route JSON before and after a `VirtualService` change and compare the two.
- Find the listener filter chain that handles mutual TLS on the inbound side.
- Point the header rule at a subset `v3` that does not exist, and follow the chain until it breaks.
