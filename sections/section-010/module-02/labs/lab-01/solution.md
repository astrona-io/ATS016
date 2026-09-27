# Solution: Widen A Policy Without Weakening The Mesh

## Step 1 — Find out what applies to the pod

Four objects exist in the namespace. Listing them says nothing about which
reach the workload or what they add up to:

```sh
kubectl -n describe-demo get virtualservice,destinationrule,peerauthentication,authorizationpolicy
```

Ask the question properly instead:

```sh
export POD=$(kubectl -n describe-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
istioctl x describe pod $POD -n describe-demo
```

```text
RBAC policies: ns[describe-demo]-policy[notification-post-only]-rule[0]
Effective PeerAuthentication:
   Workload mTLS mode: STRICT
```

The `RBAC policies` line names the exact rule that judges your requests. That is
the object to change — and `Effective PeerAuthentication` is the value the task
requires you to leave alone.

## Step 2 — Confirm it, from the proxy's own mouth

The proxy was already left at `rbac:debug`, so the decision is being logged:

```sh
kubectl -n describe-demo exec deploy/tester -- \
  curl -s -o /dev/null -X GET http://notification-service/notify
kubectl -n describe-demo logs $POD -c istio-proxy --tail=20 | grep -i rbac
```

```text
[... debug envoy rbac] enforced denied, matched policy none
```

`matched policy none` is the implicit-deny rule firing: an `ALLOW` policy
**forbids everything it does not name**, so a policy listing only `POST` refuses
`GET` without mentioning it.

## Step 3 — Widen the policy, not the mesh

Add `GET` to the permitted methods. Everything else stays as it was:

```sh
kubectl apply -f - <<'EOF'
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: notification-post-only
  namespace: describe-demo
spec:
  selector:
    matchLabels:
      app: notification-service
  action: ALLOW
  rules:
    - to:
        - operation:
            methods: ["POST", "GET"]
EOF
```

`kubectl patch` works equally well:

```sh
kubectl -n describe-demo patch authorizationpolicy notification-post-only --type json \
  -p '[{"op":"replace","path":"/spec/rules/0/to/0/operation/methods","value":["POST","GET"]}]'
```

```sh
astrona submit
```

## Step 4 — Put the log level back

A raised scope costs CPU and log volume until the pod restarts, and nothing
reminds you:

```sh
istioctl proxy-config log $POD -n describe-demo --level rbac:info
istioctl proxy-config log $POD -n describe-demo | grep '^rbac:'
```

```text
rbac: info
```

Run with no `--level`, the same command *reports* the current levels instead of
setting them — which is also how you audit a proxy somebody else was debugging.

## Step 5 — Verify all three outcomes

```sh
for M in GET POST DELETE; do
  kubectl -n describe-demo exec deploy/tester -- \
    curl -s -o /dev/null -w "$M %{http_code}\n" -X $M http://notification-service/notify
done
istioctl x describe pod $POD -n describe-demo | grep -i -A2 'Effective PeerAuthentication'
```

```text
GET 200
POST 200
DELETE 403
   Workload mTLS mode: STRICT
```

`DELETE` still refused is the part that proves you widened the policy rather
than removing it.

```sh
astrona submit
```

## Why the shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Delete the `AuthorizationPolicy` | `GET` works and so does everything else — the workload is now unprotected |
| Add `rules: [{}]` to the `ALLOW` policy | same effect: an empty rule matches every request |
| Set `PeerAuthentication` to `PERMISSIVE` | does nothing for a `403`, and quietly accepts plaintext from any caller |
| Restart the pod to clear the log level | works, and is an outage on a single-replica workload; set the level instead |

## Common mistakes

- Reading only the top of `describe` output. The warnings at the bottom are
  usually the answer.
- Expecting `describe` to show cluster-wide problems — it is a per-pod view.
- Leaving the proxy log level at `debug`. It is a real performance cost and it
  survives until the pod restarts.
- Assuming a `403` came from the application. The sidecar refused it before the
  container saw the request, which is why the application log is empty.

## Practice variations

- Break the Service port name and re-run `describe` to see the protocol warning.
- Use `--level connection:debug` and follow a single connection through the log.
- Compare `describe` output for a meshed and an unmeshed pod.
- Produce a scoped `istioctl bug-report --include describe-demo --since 10m` and
  list what it collected.
