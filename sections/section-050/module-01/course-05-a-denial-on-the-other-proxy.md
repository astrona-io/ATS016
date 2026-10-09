# A Denial On The Other Proxy

Timeouts, circuit breakers and routing misses are all decided by the client's proxy. An authorization denial is different. It happens on the **destination's** side, after the request has crossed the network. The client's access log line tells you almost nothing about why, so you have to read the destination proxy's log. This part produces that denial, cleans up the namespace, and reads the whole window of traffic at once.

## An authorization denial

An **`AuthorizationPolicy`** is the Istio resource that allows or denies requests to a workload, by caller, operation and conditions. A policy with the action `DENY` and one empty rule (`- {}`) matches every request, so it denies every request to the workloads it selects. The destination's sidecar proxy enforces the policy, so the destination's proxy is also the one that writes down why.

<!-- astrona:playground:renew -->

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

Then check the result. The `VirtualService` that matches only `/reports` is still applied, so send the request to `/reports/today`, which it routes. Wait a few seconds for the policy to reach the destination's proxy, send one request, and read the newest line on both sides:

```sh
sleep 3
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/reports/today
echo '--- client ---'
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
echo '--- destination ---'
kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy --tail=1
```

You should see something like:

```text
403
--- client ---
[...] "POST /reports/today HTTP/1.1" 403 - via_upstream - ... "10.244.0.12:8084" outbound|80||notification-service...
--- destination ---
[...] "POST /reports/today HTTP/1.1" 403 - rbac_access_denied_matched_policy[ns[accesslog-demo]-policy[deny-all]-rule[0]] ... inbound|8084||
```

Both proxies wrote a line, both show the flag `-`, and both are right: at the connection level nothing went wrong. The destination's proxy refused the request after it arrived. The client's line looks like an ordinary `403` that came back from the upstream (`via_upstream`). Only the destination's response code details field carries `rbac_access_denied_matched_policy[...]`, which names the namespace, the policy and the number of the rule that refused the request.

`istioctl x describe pod` prints the policies that apply to one workload, so you can match the log line to the policy that the destination's proxy enforces. A `403` with the flag `-` on both sides is a failure the flag table cannot explain. The details field on the right proxy can, and that is why you always ask which proxy wrote the line.

## Cleaning up, and reading the whole window

Test configuration stays in effect until you delete it. This step removes the deny-all policy, the `VirtualService` and the circuit breaker `DestinationRule`. Then it proves traffic works again and counts the flags in the `tester` pod's last 60 lines:

```sh
kubectl -n accesslog-demo delete authorizationpolicy deny-all
kubectl -n accesslog-demo delete virtualservice notification
kubectl -n accesslog-demo delete destinationrule notification
sleep 3
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=60 \
  | awk '{print $6}' | sort | uniq -c | sort -rn
```

If you skipped one of the earlier examples, `kubectl` reports that the object is not found. That is fine; carry on.

The request returns `200`, so traffic works again. The count below it is a short history of what you did in this module: mostly `UO` and `-`, plus one `UT` and one `NR`. Your numbers will differ, because the `UO` count depends on timing. On a real incident, the same command over a longer window is the fastest way to see which failure is most common. A mix of `-` and `UO` reads as a capacity problem; a wall of `UF` reads as connectivity or mTLS.

## The four, side by side

Put the four failures next to each other, and one column decides where you look next: did the destination's proxy write a line?

| Flag | Status | Duration | Upstream host | Destination logged? |
| --- | --- | --- | --- | --- |
| `UT` | `504` | about the timeout | an address | yes, usually with `DC` |
| `UO` | `503` | `0` | `-` | no |
| `NR` | `404` | `0` | `-` | no |
| `-` (RBAC) | `403` | small | an address | **yes, with the reason** |

Two of the four never reached the destination: the client's proxy decided them from its own configuration. The timeout reached the destination, but the client's proxy gave up. Only the authorization denial was decided by the destination's proxy, and only its line says why. That split is the practical meaning of "which proxy wrote the line", and it tells you where to look next before you know anything else.

You now know where each failure is decided and which log explains it. The client's proxy decides timeouts, circuit breaker rejections and routing misses, and its own line shows the flag. The destination's proxy decides authorization, and only its response code details name the policy. The same habit of reading both sides is what finds the hardest failure of all: a connection that the destination refuses before any request exists.

## Common pitfalls

> [!WARNING]
> - **Reading only the client's log for a `403`.** The client's line looks ordinary; the destination's details field is the answer.
> - **Reading the `-` flag as "nothing happened".** With a `403`, it means the connection was fine and a policy refused the request.
> - **Leaving a deny-all policy behind.** It stays in effect until you delete it, and it blocks every caller of the workload.
> - **Checking straight after applying a policy.** The destination's proxy needs a moment to receive it; wait a few seconds before you test.

## Your mission: Find Which Proxy Refused The Request

You can now tell a failure the client's proxy decides from one the destination's proxy decides, and read the reason on the right side. The graded lab gives you a namespace where single requests get `403` and bursts of requests get `503`, and asks you to find each cause in the access logs and fix it without removing the policy or the connection pool.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-050-01
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-01/labs/lab-02
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-02
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-050-01-02
astrona start ats-016-playground-050-01
```
