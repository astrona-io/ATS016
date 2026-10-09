# Solution: Widen A Policy Without Weakening The Mesh

Work the task yourself first, astronaut. Running `astrona submit -c sections/section-010/module-02/labs/lab-01` after a step tells you which checks pass, without telling you what is left.

The grader checks three things: `GET` and `POST` return `200` while `DELETE` returns `403` (and the policy still exists), the mutual TLS mode is still `STRICT`, and the `rbac` log scope is back at `info`.

## Step 1: Find out what applies to the pod

Four objects exist on the planet. Listing them says nothing about which ones reach the workload, or what they add up to:

```sh
kubectl -n describe-demo get virtualservice,destinationrule,peerauthentication,authorizationpolicy
```

Ask for the ship's dossier instead. First store the pod name, then describe it:

```sh
export POD=$(kubectl -n describe-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
istioctl x describe pod $POD -n describe-demo
```

The lines that matter (the output is shortened):

```text
RBAC policies: ns[describe-demo]-policy[notification-post-only]-rule[0]
Effective PeerAuthentication:
   Workload mTLS mode: STRICT
```

The `RBAC policies` line names the exact rule that judges your requests. That is the object to change. `Effective PeerAuthentication` is the value the task says you must leave alone.

## Step 2: Confirm it from the proxy's own words

The proxy was left at `rbac:debug`, so it already logs its authorization decisions. Send a `GET` and read the log:

```sh
kubectl -n describe-demo exec deploy/tester -- \
  curl -s -o /dev/null -X GET http://notification-service/notify
kubectl -n describe-demo logs $POD -c istio-proxy --tail=20 | grep -i rbac
```

```text
[... debug envoy rbac] enforced denied, matched policy none
```

`matched policy none` is the implicit deny at work. An `ALLOW` policy **forbids everything it does not name**, so a policy that lists only `POST` refuses `GET` without ever mentioning it.

## Step 3: Widen the policy, not the mesh

Add `GET` to the allowed methods. Everything else stays as it was.

Save this as `authorizationpolicy-notification-post-only.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f authorizationpolicy-notification-post-only.yaml
```

A `kubectl patch` works just as well, if you prefer it:

```sh
kubectl -n describe-demo patch authorizationpolicy notification-post-only --type json \
  -p '[{"op":"replace","path":"/spec/rules/0/to/0/operation/methods","value":["POST","GET"]}]'
```

## Step 4: Put the log level back

A raised scope costs processor time and log volume until the pod restarts, and nothing reminds you. Set it back and check:

```sh
istioctl proxy-config log $POD -n describe-demo --level rbac:info
istioctl proxy-config log $POD -n describe-demo | grep '^rbac:'
```

```text
rbac: info
```

Run with no `--level`, the same command *reports* the current levels instead of setting them. That is also how you check a proxy somebody else was debugging. If your `istioctl` prints the scopes indented under an `active loggers:` heading, the `^` in the `grep` matches nothing; drop it and look for the `rbac` line.

## Step 5: Check all three outcomes

Send `GET`, `POST` and `DELETE`, then read the effective mutual TLS mode:

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

`DELETE` still being refused proves you widened the policy instead of removing it.

## Step 6: Submit

Send the mission for grading:

```sh
astrona submit -c sections/section-010/module-02/labs/lab-01
```

## Why the shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Delete the `AuthorizationPolicy` | `GET` works, and so does everything else; the workload is now unprotected |
| Add `rules: [{}]` to the `ALLOW` policy | the same effect: an empty rule matches every request |
| Set the `PeerAuthentication` to `PERMISSIVE` | does nothing for a `403`, and quietly accepts plain text from any caller |
| Restart the pod to clear the log level | works, but it is an outage on a workload with one replica; set the level instead |

## Common mistakes

- Reading only the top of the `describe` output. The warnings at the bottom are often the answer.
- Expecting `describe` to show problems across the cluster. It shows one pod.
- Leaving the proxy log level at `debug`. It is a real performance cost and lasts until the pod restarts.
- Assuming a `403` came from the application. The sidecar refused it before the container saw the request, which is why the application log is empty.

## Practice on your own

- Break the Service port name and run `describe` again to see the protocol warning.
- Use `--level connection:debug` and follow a single connection through the log.
- Compare the `describe` output for a pod in the mesh and a pod outside it.
- Produce a limited `istioctl bug-report --include describe-demo --since 10m` and list what it collected.
