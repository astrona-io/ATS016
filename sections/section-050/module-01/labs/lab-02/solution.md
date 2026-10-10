# Solution: Find Which Proxy Refused The Request

Work the task yourself first. Running `astrona submit -c sections/section-050/module-01/labs/lab-02` after a step tells you which checks pass, without telling you what is left.

The grader checks three things: ten `POST` requests in a row return `200`; the `DENY` policy `block-delete` still exists and a `DELETE` returns `403`; and the `DestinationRule` keeps a connection pool while twenty `POST` requests sent at the same time all return `200`.

## Step 1: Read the 403 on both proxies

Send one `POST`, then read the newest access log line of the client's proxy and of the destination's proxy:

```sh
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
sleep 2
echo '--- client ---'
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
echo '--- destination ---'
kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy --tail=1
```

The output looks something like this (the log lines are shortened):

```text
403
--- client ---
[...] "POST /notify HTTP/1.1" 403 - via_upstream - ... outbound|80||notification-service...
--- destination ---
[...] "POST /notify HTTP/1.1" 403 - rbac_access_denied_matched_policy[ns[accesslog-demo]-policy[block-delete]-rule[0]] ... inbound|8084||
```

Both proxies wrote a line, and both show the flag `-`, so the connection worked and the request reached the destination. The client's line only says `via_upstream`: the `403` came back from the other side. The destination's response code details name the decision: the policy `block-delete` in `accesslog-demo`, rule `0`. So the **destination's proxy** refused the request, because of an `AuthorizationPolicy`.

## Step 2: Fix the policy without removing it

Read the rule of the policy:

```sh
kubectl -n accesslog-demo get authorizationpolicy block-delete -o jsonpath='{.spec.action} {.spec.rules}{"\n"}'
```

```text
DENY [{"to":[{"operation":{"methods":["POST"]}}]}]
```

The policy is meant to block `DELETE`, but its rule lists `POST`. A `DENY` policy refuses every request that matches a rule, so every `POST` is refused. Replace the method in the rule:

```sh
kubectl -n accesslog-demo patch authorizationpolicy block-delete --type json \
  -p '[{"op":"replace","path":"/spec/rules/0/to/0/operation/methods","value":["DELETE"]}]'
```

Wait a few seconds for the destination's proxy to receive the change, then send a `POST` and a `DELETE`:

```sh
for METHOD in POST DELETE; do
  kubectl -n accesslog-demo exec deploy/tester -- \
    curl -s -o /dev/null -w "$METHOD %{http_code}\n" -X $METHOD http://notification-service/notify
done
```

`POST` should now return `200` and `DELETE` should return `403`. Deleting the policy would also make `POST` work, but then nothing refuses `DELETE`, and the grader checks for that.

Submit to see the first checks pass:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-02
```

## Step 3: Read the 503 under a burst

Send twenty `POST` requests at the same time, then count the response flags in the client's last 20 lines:

```sh
kubectl -n accesslog-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -X POST http://notification-service/notify & done; wait'
sleep 2
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=20 \
  | awk '{print $6}' | sort | uniq -c | sort -rn
```

Field `$6` is the response flag in the default format. The count shows some `-` (requests that got through) and some `UO`. The exact numbers change from run to run, because they depend on timing. Print one of the `UO` lines:

```sh
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=20 | grep ' UO ' | head -1
```

The line shows `503 UO upstream_overflow`, a duration of `0` and an upstream host of `-`. The **client's proxy** refused the request at once, before it contacted the destination, so the destination's proxy has no line for it. `UO` means upstream overflow: a circuit breaker limit in a `DestinationRule` was full.

## Step 4: Raise the limits, keep the pool

Read the connection pool of the `DestinationRule`:

```sh
kubectl -n accesslog-demo get destinationrule notification -o jsonpath='{.spec.trafficPolicy.connectionPool}{"\n"}'
```

```text
{"http":{"http1MaxPendingRequests":1,"maxRequestsPerConnection":1},"tcp":{"maxConnections":1}}
```

One connection and one waiting request cannot carry a burst of twenty. The platform needs a limit, so raise it instead of removing it:

```sh
kubectl -n accesslog-demo patch destinationrule notification --type merge \
  -p '{"spec":{"trafficPolicy":{"connectionPool":{"tcp":{"maxConnections":100},"http":{"http1MaxPendingRequests":100}}}}}'
```

A merge patch changes only the fields it names, so `maxRequestsPerConnection` stays as it was. Wait a few seconds, then send the burst again and count the flags:

```sh
kubectl -n accesslog-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code}\n" -X POST http://notification-service/notify & done; wait' \
  | sort | uniq -c
```

All twenty requests should now return `200`.

Submit again. All three checks should pass:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-02
```

## Why the obvious shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Delete `block-delete` | `POST` works, and `DELETE` is no longer refused; the grader checks that `DELETE` returns `403` |
| Change `block-delete` to `ALLOW` with `POST` | `DELETE` and every other method not listed are refused; the grader requires a `DENY` policy |
| Delete the `DestinationRule` | the burst works, and the platform loses its connection limit; the grader requires `maxConnections` |
| Read only the client's log for the `403` | the line looks ordinary; only the destination's details name the policy |

## Common mistakes

- Treating both failures as one problem. The `403` is decided by the destination's proxy, the `503` by the client's proxy, and each has its own fix.
- Looking for the `UO` request in the destination's log. The client's proxy refused it, so the destination never saw it.
- Expecting an exact `UO` count. It depends on timing.
- Testing straight after a change. The proxies need a few seconds to receive the new configuration.
