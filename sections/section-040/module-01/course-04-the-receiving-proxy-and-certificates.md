# The Receiving Proxy And Its Certificates

Astronaut, so far you have read only the **client** side: one communications officer deciding where to send a signal. The destination ship has a communications officer too. Its orders are a different set of objects, and a whole class of problems is invisible unless you look there. This part covers that receiving side, and the certificates both ends rely on for the secret handshake.

## Two proxies, one request

Every signal between two meshed ships passes two proxies, and each one applies different rules:

```text
   tester pod                                    notification-service pod
   ┌──────────────────┐                          ┌──────────────────┐
   │ app              │                          │        app :8084 │
   │  │               │                          │            ▲     │
   │  ▼  OUTBOUND     │      mTLS over the       │   INBOUND  │     │
   │ envoy :15001 ────┼───── pod network ────────┼──▶ envoy :15006  │
   │  listener        │                          │    listener      │
   │  → route         │                          │    → filter chain│
   │  → cluster       │                          │    → cluster     │
   │  → endpoint      │                          │      inbound|8084||
   └──────────────────┘                          └──────────────────┘
        applies:                                      applies:
        VirtualService                                PeerAuthentication
        DestinationRule                               AuthorizationPolicy
        retries, timeouts,                            RequestAuthentication
        circuit breaking, LB
```

The split is not random. **Client-side policy** is about how to reach a destination, so it belongs to the ship doing the reaching. **Server-side policy** is about who may do what to this workload, so the workload's own proxy must enforce it. Otherwise a misbehaving client, or one with no proxy at all, could simply skip it.

Server-side policy includes `PeerAuthentication` (the airlock rule that demands the secret handshake, mutual TLS or mTLS) and `AuthorizationPolicy` (the guard's list at the airlock). That one fact explains the most common wasted hour in Istio debugging: studying an `AuthorizationPolicy` in the caller's configuration, where it does not appear and never will.

## Inbound configuration

The receiving side is simpler than the sending side. There is one listener (15006) and one cluster for each app port. This section shows both and the policy they carry.

<!-- astrona:playground:renew -->

### See the receiving side

Ask the app's ship for its 15006 listener and its inbound clusters:

```sh
istioctl proxy-config listener deploy/notification-service-v1 -n proxycfg-demo --port 15006 | head -5
istioctl proxy-config cluster deploy/notification-service-v1 -n proxycfg-demo | grep inbound
```

You should see something like:

```text
ADDRESSES  PORT   MATCH                                                    DESTINATION
0.0.0.0    15006  Addr: *:8084                                             Cluster: inbound|8084||

SERVICE FQDN   PORT  SUBSET  DIRECTION  TYPE          DESTINATION RULE
               8084  -       inbound    ORIGINAL_DST
```

The inbound cluster is named `inbound|8084||`. It uses the same four-field naming as outbound clusters, with no FQDN and no subset, because the destination is this pod's own app. Its type is `ORIGINAL_DST`: it sends the connection on to the address it was first headed for, which is how one listener serves every app port. The `MATCH` value `Addr: *:8084` is filter chain matching on that recovered original destination port.

A missing `inbound|<port>||` cluster is a clear finding: traffic arrives at the pod and never reaches the container. The usual causes are a Service that does not expose that port, or a port whose protocol could not be worked out.

### Filter chains carry the policy

The 15006 listener's filter chains are where server-side policy actually lives. List the filter names in its JSON:

```sh
istioctl proxy-config listener deploy/notification-service-v1 -n proxycfg-demo \
  --port 15006 -o json | grep -E '"name": "envoy\.filters' | sort -u
```

Among the results you find the authorization filter (`envoy.filters.http.rbac`), and the transport socket settings that carry out mutual TLS. When a destination refuses a handshake in an mTLS mismatch, this listener is the object doing the refusing. Whether those filters are present, and how they are set, is what `PeerAuthentication` and `AuthorizationPolicy` control.

## Certificates

`istioctl proxy-config secret` prints the certificates a proxy holds right now: its own workload certificate (its ID badge) and the root certificate it checks other badges against (the fleet's official seal). It reads the same live administration interface as every other `proxy-config` subcommand.

### See your test ship's ID badge

Ask the `tester` proxy for its secrets:

```sh
istioctl proxy-config secret deploy/tester -n proxycfg-demo
```

You should see something like:

```text
RESOURCE NAME     TYPE           STATUS     VALID CERT     SERIAL NUMBER    NOT AFTER                NOT BEFORE
default           Cert Chain     ACTIVE     true           2f1a...          2026-09-28T09:14:22Z     2026-09-27T09:12:22Z
ROOTCA            CA             ACTIVE     true           7c04...          2036-09-24T08:50:11Z     2026-09-26T08:50:11Z
```

`default` is this workload's own certificate. Notice that it is valid for only about **24 hours**: `istiod` (mission control's badge office) issues short-lived badges and swaps them before they expire. `ROOTCA` is the mesh root, valid for years. `VALID CERT: false`, a `NOT AFTER` time in the past, or an empty list is a definite answer, not a hint.

The table supports two more readings. Comparing `NOT BEFORE` with the pod's age shows whether the badge has been swapped at least once, which is useful after a control plane incident. And `-o json` includes the certificate's Subject Alternative Name (SAN), which carries the workload's SPIFFE identity (`spiffe://<trust-domain>/ns/<namespace>/sa/<serviceaccount>`). That is the exact string an `AuthorizationPolicy` `principals` rule matches against, so it is the fastest way to check why such a rule does not match.

## Common pitfalls

> [!WARNING]
> - **Looking only at the client proxy.** `PeerAuthentication` and `AuthorizationPolicy` are enforced inbound. The sender's configuration cannot show you why a policy denied a request.
> - **Expecting the app's port as an inbound listener.** There is one inbound listener, 15006, and the app's port is a match rule on it, plus an `inbound|<port>||` cluster.
> - **Forgetting the certificate clock.** A workload certificate is valid for about a day. An expired one explains a mesh-wide failure with no configuration change behind it.
> - **Guessing the identity a `principals` rule should match.** Read the SAN from the proxy's own certificate instead.

> *The client's configuration explains where a request was sent; only the destination's explains what was allowed to happen when it arrived.*
