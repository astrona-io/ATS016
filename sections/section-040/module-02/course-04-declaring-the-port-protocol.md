# Declaring The Port Protocol

A missing subset gives a loud failure: every request returns `503` with the flag `NC`. A Service port with the wrong protocol gives a quiet one. Requests succeed with `200`, and every HTTP rule in the `VirtualService` for that host does nothing. Nothing about the symptom points at the Service definition, so this part shows how Istio decides a port's protocol, what happens when it decides "TCP", and how to see it in the proxy.

## How Istio decides a port's protocol

Istio decides how to handle traffic on a port from the Service, in this order:

1. The port's **`appProtocol`** field, for example `appProtocol: http`. If it is set, it wins.
2. The port's **`name`**, in the form `<protocol>[-<suffix>]`, for example `http`, `http-notify`, `grpc` or `tcp-db`.
3. If neither declares a known protocol, for example a port named `web` or a port with no name, Istio uses **automatic protocol detection**: Envoy reads the first bytes of each connection and treats it as HTTP if it looks like HTTP, otherwise as plain TCP.

Automatic detection works for plain HTTP, so a port named `web` that carries HTTP still gets HTTP routing. It does not work for server-first protocols such as MySQL, where the server speaks first and the client sends nothing for Envoy to read. The Kubernetes `protocol: TCP` field on a port is something else: it is the transport protocol, and every HTTP port has it. Istio reads `appProtocol` and the name, not that field.

Check how the playground's Service declares its port:

<!-- astrona:playground:renew -->

```sh
kubectl -n fivezerothree-demo get svc notification-service -o jsonpath='{.spec.ports}{"\n"}'
```

You should see something like:

```text
[{"name":"http","port":80,"protocol":"TCP","targetPort":8084}]
```

In this playground the port is named `http` and maps port 80 to the container port 8084. That name is why the `tester` proxy builds full HTTP routing for this Service. Keep the field in mind: it is the first thing to check when routing rules seem to be ignored.

## What goes wrong when the port is declared as TCP

When a port is declared as `tcp` (by a name such as `tcp` or `tcp-notify`, or by `appProtocol: tcp`), Istio treats it as an opaque TCP stream. The effects reach every stage of the client proxy's chain:

- The listener forwards the connection straight to a cluster, so there is **no route stage** and no `VirtualService` HTTP rule applies.
- No HTTP filters run, so retries, timeouts and header-based routing are gone.
- No HTTP metrics are recorded, so the Service shows only TCP traffic on dashboards.
- Requests still succeed, because the bytes still reach a pod. The `200` hides the problem.

The last point is what makes this failure expensive. Traffic works, so nobody investigates, and every routing rule written for that Service does nothing at all. You can see it in the playground. The routing there now sends every request to `v1`, so the commands below show the change in the proxy rather than in the responses. Rename the port to `tcp`:

```sh
kubectl -n fivezerothree-demo patch svc notification-service --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/name","value":"tcp"}]'
```

```text
service/notification-service patched
```

Then look at the listener and route stages on the `tester` proxy:

```sh
istioctl proxy-config listener deploy/tester -n fivezerothree-demo --port 80
istioctl proxy-config route deploy/tester -n fivezerothree-demo -o json | grep -c 'notification-service.fivezerothree-demo'
```

You should see something like:

```text
ADDRESSES     PORT MATCH                                DESTINATION
0.0.0.0       80   Trans: raw_buffer; App: http/1.1,h2c Route: 80
0.0.0.0       80   ALL                                  PassthroughCluster
10.96.187.226 80   ALL                                  Cluster: outbound|80||notification-service.fivezerothree-demo.svc.cluster.local
0
```

The listener now has a third line, bound to the ClusterIP of `notification-service` (`10.96.187.226` here; yours will differ). It matches `ALL` and hands off straight to the cluster `outbound|80||notification-service...`, with no `Route:`, so the subset routing of the `VirtualService` is skipped. The route count is `0`: no route configuration in the `tester` proxy has a virtual host for `notification-service` any more. `grep -c` exits with code `1` when it counts `0`, which is expected here. Put the name back before you go on:

```sh
kubectl -n fivezerothree-demo patch svc notification-service --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/name","value":"http"}]'
```

No restart is needed in either direction. `istiod` rebuilds the proxies' listeners and routes and pushes them over xDS within a few seconds.

## How to spot it

There are three signs, from fastest to slowest. The listener stage shows it directly: an HTTP port has the match `Trans: raw_buffer; App: http/1.1,h2c` and hands off to a `Route:`, while a TCP port hands straight to a `Cluster:`. `istioctl x describe pod` prints each Service port with the protocol Istio uses, for example `80/HTTP` or `80/TCP`. And the route table simply has no virtual host for that Service on that port.

The listener sign is the one to remember. When a `VirtualService` is ignored rather than wrong, check whether the listener for its port hands off to a `Route:` at all.

The fix is a change to the Service, not to the `VirtualService`: give the port a name that declares the protocol, such as `http`, or set `appProtocol: http`. Change only how the port is declared, never the port numbers. Declaring every port explicitly is good practice even when automatic detection would work, because the declaration also makes the protocol visible to the next person who reads the Service.

You now know two causes of "my routing does not work": a route that names a cluster that does not exist, which fails loudly with `NC`, and a port declared as TCP, which removes the route stage and fails quietly with `200`. You also know how Istio reads `appProtocol`, then the port name, then falls back to automatic detection. Finding a port declared as TCP in the proxy and fixing it is a skill you can now prove on your own.

## Common pitfalls

> [!WARNING]
> - **Rewriting a `VirtualService` that is never read.** If the listener has no `Route:` for the port, no edit to the `VirtualService` can help.
> - **Trusting a `200` as proof that routing applies.** A TCP port also returns `200`. Check the listener for a `Route:` hand-off.
> - **Confusing `protocol: TCP` with the Istio protocol.** The Kubernetes `protocol` field is the transport protocol; Istio reads `appProtocol` and the port name.
> - **Changing the port numbers instead of the declaration.** The fix is the name or `appProtocol`; the port and target port stay the same.
> - **Leaving server-first protocols to automatic detection.** Declare them explicitly, for example `tcp-mysql` or `appProtocol: mysql`.

## Your mission: Declare The Service Port Protocol So The Route Applies

You can now find a port that Istio handles as TCP and fix its declaration so HTTP routing applies. The graded lab gives you two versions of `notification-service` with correct header routing that is ignored, and asks you to find the cause in the `tester` proxy and fix it without touching the `VirtualService` or the port numbers.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-040-02
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/module-02/labs/lab-02
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-040/module-02/labs/lab-02
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-040-02-02
astrona start ats-016-playground-040-02
```
