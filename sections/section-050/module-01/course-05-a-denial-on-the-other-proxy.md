# A Denial On The Other Proxy

Astronaut, timeouts, circuit breakers and routing misses are all decided by the communications officer on the sending ship. This last drill is different in kind. An authorization denial happens on the **destination** side, after the signal has crossed the network. The client's flight log tells you almost nothing about why, so you have to read the other ship's log.

## An authorization denial

An **`AuthorizationPolicy`** is the guard's list at the airlock: who may come aboard and what they may do. A policy with the action `DENY` and an empty rule (`- {}`) turns every signal away. The destination's sidecar proxy enforces it, so the destination's proxy is the one that writes down why.

<!-- astrona:playground:renew -->

### The same request, two very different log lines

Save this as `authorizationpolicy-deny-all.yaml`:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: accesslog-demo
spec:
  selector:
    matchLabels:
      app: notification-service
  action: DENY
  rules:
    - {}
```

Apply it:

```sh
kubectl apply -f authorizationpolicy-deny-all.yaml
```

Then check the result. Wait a few seconds for the policy to reach the proxy, send one request, and read the newest line on both sides:

```sh
sleep 3
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
echo '--- client ---'
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
echo '--- destination ---'
kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy --tail=1
```

You should see something like:

```text
403
--- client ---
[...] "POST /notify HTTP/1.1" 403 - via_upstream - ... "10.244.0.12:8084" outbound|80||notification-service...
--- destination ---
[...] "POST /notify HTTP/1.1" 403 - rbac_access_denied_matched_policy[ns[accesslog-demo]-policy[deny-all]-rule[0]] ... inbound|8084||
```

Both proxies wrote a line, both show the flag `-`, and both are right: at the connection level nothing went wrong. The guard turned the signal away at the airlock. The client's line looks like an ordinary `403` passed back. Only the destination's response code details field carries `rbac_access_denied_matched_policy[...]`, which names the namespace, the policy and the number of the rule that refused the request.

`istioctl x describe pod` prints the same policy identifier for a workload, so you can match the log line to the policy that the destination enforces.

A flag of `-` on both sides with a `403` in the middle is a failure the flag table cannot explain. The details field on the *right* proxy can, and that is why you always ask which proxy wrote the line.

## Cleaning up, and reading the whole window

Drill configuration stays in effect until you delete it. This step removes the deny-all policy and the circuit breaker `DestinationRule`, proves traffic works again, and counts what the drills left in the flight log.

### Remove the drills and count what happened

Delete both objects, wait a moment, send one request, and count the flags in the tester's last 60 lines:

```sh
kubectl -n accesslog-demo delete authorizationpolicy deny-all
kubectl -n accesslog-demo delete destinationrule notification
sleep 3
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=60 \
  | awk '{print $5}' | sort | uniq -c | sort -rn
```

If you never created the `notification` `DestinationRule` (the circuit breaker with a pool of one), `kubectl` reports that it is not found. That is fine; carry on.

You should see something like:

```text
200
  31 UO
  14 -
   1 UT
   1 NR
```

Traffic works again, and the count is a short history of your drills. On a real incident, the same command over a longer window is the fastest way to see which failure is most common. A mix of `-` and `UO` reads as a capacity problem; a wall of `UF` reads as connectivity or mutual TLS.

## The four, side by side

Put the four drills next to each other and one column decides where you look next: did the destination write a line?

| Flag | Status | Duration | Upstream host | Destination logged? |
| --- | --- | --- | --- | --- |
| `UT` | `504` | about the timeout | `-` | no |
| `UO` | `503` | `0` | `-` | no |
| `NR` | `404` | `0` | `-` | no |
| RBAC (`-`) | `403` | small | an address | **yes** |

Read the last two columns. Three of the four never contacted the destination: the client's own proxy decided them, from its own configuration. Only the authorization denial crossed the network. That split is the practical meaning of "which proxy wrote the line", and it tells you where to look next before you know anything else.

## Common pitfalls

> [!WARNING]
> - **Reading only the client's log for a `403`.** The client's line looks ordinary; the destination's details field is the answer.
> - **Reading the `-` flag as "nothing happened".** With a `403`, it means the connection was fine and a policy refused the request.
> - **Leaving a deny-all policy behind.** It stays in effect until you delete it, and it blocks every caller of the workload.
> - **Checking straight after applying a policy.** The destination's proxy needs a moment to receive it; wait a few seconds before you test.

> *Three of the four failures never reach the destination, which is why the first question about any flag is still "who wrote the line?".*
