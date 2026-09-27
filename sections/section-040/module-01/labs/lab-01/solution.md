# Solution: Build The Routing, Then Prove It From The Proxy

## Step 1 — See the default behaviour first

```sh
kubectl -n proxycfg-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
```

```text
["EMAIL"]
["EMAIL","SMS"]
```

Two distinct responses: with no Istio configuration the Service load balances
across both versions. That is the baseline the routing will replace.

Look at what the proxy already holds, before you add anything:

```sh
istioctl proxy-config cluster deploy/tester -n proxycfg-demo \
  --fqdn notification-service.proxycfg-demo.svc.cluster.local
```

```text
SERVICE FQDN                                            PORT  SUBSET  DIRECTION  TYPE  DESTINATION RULE
notification-service.proxycfg-demo.svc.cluster.local    80    -       outbound   EDS
```

One cluster, empty subset field, and an empty `DESTINATION RULE` column. The
subsetless cluster always exists for a known Service; subset clusters exist only
when a `DestinationRule` creates them.

## Step 2 — Define the subsets

```sh
kubectl apply -f - <<'EOF'
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
EOF
istioctl proxy-config cluster deploy/tester -n proxycfg-demo \
  --fqdn notification-service.proxycfg-demo.svc.cluster.local
```

Two more clusters now exist, and applying a `DestinationRule` alone changed no
traffic — it created destinations, it did not route anything to them.

## Step 3 — Route to them

Specific match first, unconditional last:

```sh
kubectl apply -f - <<'EOF'
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
EOF
```

Note `exact: "true"` is **quoted**. Unquoted it is a YAML boolean, not the
string the header carries, and the rule silently never matches.

```sh
astrona submit
```

## Step 4 — Walk the four stages on the client proxy

This is the part the task is really grading. Each stage hands a name to the
next.

**Listener** — what captures the traffic:

```sh
istioctl proxy-config listener deploy/tester -n proxycfg-demo --port 80
```

```text
ADDRESSES  PORT  MATCH                                  DESTINATION
0.0.0.0    80    Trans: raw_buffer; App: http/1.1,h2c   Route: 80
0.0.0.0    80    ALL                                    PassthroughCluster
```

The HTTP chain hands off to `Route: 80`. The second entry is the non-HTTP
fallback.

**Route** — the tabular form hides match conditions, so use JSON:

```sh
istioctl proxy-config route deploy/tester -n proxycfg-demo --name 80 -o json \
  | grep -E '"exact_match"|"cluster"' | head
```

```text
"exact_match": "true",
"cluster": "outbound|80|v2|notification-service.proxycfg-demo.svc.cluster.local",
"cluster": "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local",
```

The header match is attached to `v2`, and `v1` follows as the catch-all — in the
order you wrote them.

**Cluster** — read the four fields: `direction|port|subset|fqdn`.

**Endpoint** — what the name resolves to right now:

```sh
istioctl proxy-config endpoint deploy/tester -n proxycfg-demo \
  --cluster "outbound|80|v2|notification-service.proxycfg-demo.svc.cluster.local"
```

```text
ENDPOINT           STATUS    OUTLIER CHECK   CLUSTER
10.244.0.14:8084   HEALTHY   OK              outbound|80|v2|notification-service...
```

The endpoint is on the **container** port 8084, not the Service port 80 — the
proxy connects directly to the pod, so the Service port only ever appears in the
cluster name. Quote the cluster name: `|` is a shell pipe.

## Step 5 — Confirm with traffic too

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

```sh
astrona submit
```

## Common mistakes

- Looking at the wrong proxy. Outbound routing lives on the **client**;
  authorization and inbound listeners live on the **destination**.
- Reading the short table output when the answer needs `-o json` — match
  conditions are only in the JSON.
- Searching a full `proxy-config all` dump by eye. Narrow with `--fqdn` and
  `--port` first.
- Forgetting that ports 15001, 15006, 15021 and 15090 are Istio's own and not
  your application's.
- Writing `exact: true` unquoted.

## Practice variations

- Dump the config before and after a `VirtualService` change and diff the two.
- Find the listener filter chain that handles mTLS on the inbound side.
- Point the header rule at a subset `v3` that does not exist and follow the
  chain until it breaks.
