# The Other Cause: An Undeclared Port

Astronaut, a missing subset is not the only way to get a `503` out of a healthy service. The other common cause is a **Service port whose name does not declare a protocol**. It is worth knowing well, because nothing about the symptom points at the Service definition. This part shows how Istio decides a port's protocol, what goes wrong when it cannot, and how to spot it fast.

## How Istio decides a port's protocol

Istio decides how to treat traffic on a port from two places on the Service. Think of a Service port as a radio channel on the beacon: its name tells every communications officer what kind of signal to expect on it.

- **The port's `name`.** Recognised names are `http`, `http2`, `grpc`, `tcp`, `tls`, `mongo` and others, optionally with a suffix, such as `http-notify`.
- **The port's `appProtocol` field**, for example `appProtocol: http`.

A port named `web`, or a port with no name, declares no protocol. Istio then falls back to sniffing the first bytes of each connection. Sniffing works for plain HTTP and fails for protocols that do not announce themselves in their first bytes, such as server-first protocols or TLS traffic Istio is not opening.

<!-- astrona:playground:renew -->

### Check how your playground's beacon declares its port

Print the port list of the `notification-service` Service:

```sh
kubectl -n fivezerothree-demo get svc notification-service -o jsonpath='{.spec.ports}{"\n"}'
```

In this playground the port is named `http` and maps port 80 to the container port 8084. That name is why the test ship's proxy builds full HTTP routing for this beacon. Keep the field in mind: it is the first thing to check when routing rules seem to be ignored.

## What goes wrong when the protocol is unknown

When a port is treated as plain TCP, the effects cascade through every stage of the proxy's chain:

```text
   port has no declared protocol
        │
        ├── no HTTP route is built for it       → VirtualService rules never apply
        ├── no HTTP filters are installed       → retries, timeouts, header routing gone
        ├── no HTTP telemetry                   → the service vanishes from dashboards
        └── depending on configuration          → 503, or worse: a 200 that ignored every rule
```

The last outcome is the nastiest. Traffic succeeds, so nobody investigates, and every routing rule written for that service does nothing at all.

## How to spot it

There are three tells, from fastest to slowest:

1. **`istioctl x describe pod`** reports it as a warning. It prints every rule that touches one ship on one page, the ship's dossier, and an undeclared port is on that list.
2. **`istioctl proxy-config listener`** shows the difference directly. An HTTP-aware port has the match `Trans: raw_buffer; App: http/1.1,h2c` and hands off to a named `Route:`. A port treated as TCP hands straight to a `Cluster:` and has no route at all.
3. **The route table** simply has no virtual host for that service on that port.

The listener tell is the one to remember. When a `VirtualService` is ignored rather than wrong, check whether the listener for its port hands off to a `Route:` at all.

## The fix

The fix is a one-word edit to the Service: give the port a name that declares the protocol. It needs no restart of anything, because `istiod` regenerates the proxies' listeners over xDS within a second or two. The general form, with your own namespace and Service name, is:

```sh
kubectl -n <ns> patch svc <name> --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/name","value":"http"}]'
```

Change only how the port is *declared*, never the port numbers. Setting `appProtocol: http` on the port works the same way, if you must keep the old name.

## Common pitfalls

> [!WARNING]
> - **Forgetting the port name.** An unnamed or undeclared Service port silently disables every HTTP routing rule aimed at it, and the symptoms look nothing like a naming problem.
> - **Rewriting a `VirtualService` that is never consulted.** If the listener has no `Route:` for the port, no edit to the `VirtualService` can help.
> - **Trusting a `200` as proof that routing applies.** Plain TCP passthrough also returns `200`. Check the listener for a `Route:` hand-off.
> - **Changing the port numbers instead of the name.** The fix is the declaration; the port and target port stay the same.

> *When a rule is ignored rather than wrong, look at how the port is declared before you touch the rule.*
