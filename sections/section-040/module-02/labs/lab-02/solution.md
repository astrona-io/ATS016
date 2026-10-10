# Solution: Declare The Service Port Protocol So The Route Applies

Work the task yourself first. Running `astrona submit -c sections/section-040/module-02/labs/lab-02` after a step tells you which checks pass, without telling you what is left.

The grader checks three things: the Service port declares HTTP and still maps `80` to `8084`, the `tester` proxy holds an HTTP route for `notification-service` with the header rule first, and real requests with and without the header reach the right version.

## Step 1: Confirm the symptom

Send ten requests with the header from the `tester` pod and list the different answers:

```sh
kubectl -n portproto-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST -H "testing: true" http://notification-service/notify; echo; done' | sort -u
```

```text
["EMAIL"]
["EMAIL","SMS"]
```

Both versions answer, so the header rule is not applied. Every request succeeds, which is why nobody noticed: there is no error to look for, only a rule that does nothing.

## Step 2: Check the listener and route stages on the client proxy

The `VirtualService` is applied by the **client** proxy, so ask the `tester` proxy. Start with the listeners on port 80:

```sh
istioctl proxy-config listener deploy/tester -n portproto-demo --port 80
```

Find the line for `notification-service`. Its `DESTINATION` is a `Cluster:` (`outbound|80||notification-service.portproto-demo.svc.cluster.local`), not a `Route:`. The listener forwards the connection as plain TCP bytes straight to the cluster without a subset, so there is no route stage for this host at all.

Confirm it at the route stage:

```sh
istioctl proxy-config route deploy/tester -n portproto-demo -o json | grep -c 'notification-service.portproto-demo'
```

The count is `0`: no route configuration in the `tester` proxy has a virtual host for `notification-service`. With no route stage, no `VirtualService` rule can apply, however correct it is.

## Step 3: Find out why the port is handled as TCP

Istio decides a port's protocol from the Service: first from the port's `appProtocol` field, then from its name, which has the form `<protocol>[-<suffix>]`. Read the Service's ports:

```sh
kubectl -n portproto-demo get svc notification-service -o jsonpath='{.spec.ports}{"\n"}'
```

```text
[{"name":"tcp-notify","port":80,"protocol":"TCP","targetPort":8084}]
```

The port is named `tcp-notify`, so its protocol is `tcp`. Istio treats a `tcp` port as an opaque TCP stream: it builds no HTTP filters and no HTTP route for it. The `protocol: TCP` field is the Kubernetes transport protocol and is not the problem; every HTTP port has it.

## Step 4: Fix the declaration

Rename the port to `http`. The port number and the target port stay the same:

```sh
kubectl -n portproto-demo patch svc notification-service --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/name","value":"http"}]'
```

Setting `appProtocol: http` on the port works too, because `appProtocol` takes precedence over the name. No restart is needed: `istiod` pushes new listeners and routes to the proxies over xDS within a few seconds. You can send it for grading now to see where you stand:

```sh
astrona submit
```

## Step 5: Prove it from the proxy and with traffic

Check the route stage again, then send ten requests with the header and ten without:

```sh
istioctl proxy-config route deploy/tester -n portproto-demo -o json \
  | grep -E '"exact"|"cluster": "outbound\|80\|v'
kubectl -n portproto-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST -H "testing: true" http://notification-service/notify; echo; done' | sort -u
kubectl -n portproto-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
```

The route JSON now has the `testing` header match with the `v2` cluster, followed by the `v1` cluster. The requests show one answer each:

```text
["EMAIL","SMS"]
["EMAIL"]
```

Every request with the header reached `v2`, and every request without it reached `v1`. Send the final answer for grading:

```sh
astrona submit
```

## Why the obvious shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Rewrite or recreate the `VirtualService` | nothing changes: the proxy has no route stage for this port, so it never reads the rule |
| Change the port to `8084` or another number | callers on port `80` break, and the grader requires `80` to `8084` |
| Rename the port to something without a protocol, such as `web` | Istio falls back to automatic protocol detection, which works for plain HTTP, but the grader requires an explicit HTTP declaration |
| Restart the pods | nothing changes: the protocol comes from the Service, not from the pods |

## Common mistakes

- **Reading the `VirtualService` again and again.** When a rule is ignored rather than wrong, check the listener first.
- **Confusing `protocol: TCP` with the Istio protocol.** The Kubernetes `protocol` field is the transport protocol. Istio reads `appProtocol` and the port name.
- **Trusting a `200` as proof that routing applies.** A TCP port also returns `200`; only the listener and route stages show whether HTTP routing exists.

## Practice on your own

- Set `appProtocol: tcp` on the fixed port while it is still named `http`, and predict which one wins before you check the listener.
- Rename the port to `web` and check whether the header rule applies. Then explain why Istio's automatic detection makes it work for plain HTTP.
