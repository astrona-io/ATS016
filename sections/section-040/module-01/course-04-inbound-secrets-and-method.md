# Part 4 — The Inbound Direction, Certificates And Method

> Prerequisite: [Part 3 — Clusters And Endpoints](./course-03-clusters-and-endpoints.md). Next: [the module landing page](./course.md), then [module 040-02](../module-02/course.md).

Everything so far has been the **client** side — one proxy deciding where to send a request. The destination pod has a proxy too, its configuration is a different set of objects, and a whole class of problems is invisible unless you look at it. This part covers that direction, the certificates both ends rely on, and how to walk the four stages as a procedure.

## Two proxies, one request

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

The division is not arbitrary. **Client-side policy** is about how to reach a destination, so it belongs to whoever is doing the reaching. **Server-side policy** is about who may do what to this workload, so it must be enforced by the workload's own proxy — otherwise a misbehaving or unmeshed client could simply skip it.

That single fact produces the most common wasted hour in Istio debugging: investigating an `AuthorizationPolicy` by examining the caller's configuration, where it does not appear and never will.

## Inbound configuration

The receiving side is simpler than the sending side. There is one listener (15006) and, per application port, one cluster.

> [!TIP]
> **Try it — the receiving side**
>
> ```sh
> istioctl proxy-config listener deploy/notification-service-v1 -n proxycfg-demo --port 15006 | head -5
> istioctl proxy-config cluster deploy/notification-service-v1 -n proxycfg-demo | grep inbound
> ```
>
> Expect something like:
>
> ```text
> ADDRESSES  PORT   MATCH                                                    DESTINATION
> 0.0.0.0    15006  Addr: *:8084                                             Cluster: inbound|8084||
>
> SERVICE FQDN   PORT  SUBSET  DIRECTION  TYPE          DESTINATION RULE
>                8084  -       inbound    ORIGINAL_DST
> ```
>
> The inbound cluster is named `inbound|8084||` — the same four-field convention from [Part 3](./course-03-clusters-and-endpoints.md), with no FQDN and no subset, because the destination is this pod's own application. Its type is `ORIGINAL_DST`: it sends the connection to the address it was originally headed for, which is how one listener serves every application port. The `MATCH` column, `Addr: *:8084`, is the chain-matching from [Part 1](./course-01-capture-and-listeners.md) applied to the recovered original destination.

A missing `inbound|<port>||` cluster is a definite finding: traffic arrives at the pod and never reaches the container. The usual causes are a Service that does not expose that port, or a port whose protocol could not be determined.

### Filter chains carry the policy

The 15006 listener's filter chains are where server-side policy actually lives, and the JSON makes that concrete:

```sh
istioctl proxy-config listener deploy/notification-service-v1 -n proxycfg-demo \
  --port 15006 -o json | grep -E '"name": "envoy\.filters' | sort -u
```

You will see the authorization filter (`envoy.filters.http.rbac`) and the transport-socket configuration that implements mTLS. When [module 050-02](../../section-050/module-02/course.md) describes an mTLS mismatch as the destination refusing a handshake, this is the object doing the refusing — and its presence or absence in the chain is what `PeerAuthentication` controls.

## Certificates

`istioctl proxy-config secret` prints the certificates a proxy currently holds: its own workload certificate and the root it validates peers against. It reads the same admin interface as everything else in this module, so the answer is live.

> [!TIP]
> **Try it — the proxy's identity**
>
> ```sh
> istioctl proxy-config secret deploy/tester -n proxycfg-demo
> ```
>
> Expect something like:
>
> ```text
> RESOURCE NAME     TYPE           STATUS     VALID CERT     SERIAL NUMBER    NOT AFTER                NOT BEFORE
> default           Cert Chain     ACTIVE     true           2f1a...          2026-09-28T09:14:22Z     2026-09-27T09:12:22Z
> ROOTCA            CA             ACTIVE     true           7c04...          2036-09-24T08:50:11Z     2026-09-26T08:50:11Z
> ```
>
> `default` is this workload's own certificate — note the roughly **24-hour** validity, which is the concrete form of [module 030-01's](../../section-030/module-01/course-01-the-four-jobs-of-istiod.md) certificate clock. `ROOTCA` is the mesh root, valid for years. `VALID CERT: false`, an expired `NOT AFTER`, or an empty list is a definite answer rather than a hint.

Two extra readings this table supports. Comparing `NOT BEFORE` against the pod's age shows whether rotation has happened at least once — useful after a control plane incident. And `-o json` includes the certificate's SAN, which carries the workload's SPIFFE identity (`spiffe://<trust-domain>/ns/<namespace>/sa/<serviceaccount>`) — the exact string an `AuthorizationPolicy` `principals` rule matches against, and therefore the fastest way to check why such a rule is not matching.

## The four-stage walk, as a procedure

Given "requests to `notification-service` are failing from `tester`", on the **client** proxy:

```text
   1. LISTENER   istioctl proxy-config listener deploy/tester -n <ns> --port 80
                 Is there an HTTP listener for that port?
                 No → the traffic is not being captured as HTTP. Check port naming, exclusions.

   2. ROUTE      istioctl proxy-config route deploy/tester -n <ns> --name 80 -o json
                 Which cluster does the matching rule name? Which VirtualService produced it?
                 Note the EXACT cluster name — the next step needs it.

   3. CLUSTER    istioctl proxy-config cluster deploy/tester -n <ns> --fqdn <host>
                 Does that cluster exist?
                 No → a missing subset or host. Fix the reference (module 040-02).

   4. ENDPOINT   istioctl proxy-config endpoint deploy/tester -n <ns> --cluster "<name>"
                 Any endpoints? HEALTHY? OUTLIER CHECK OK?
                 Empty → selector, readiness, or subset labels. Ejected → this client gave up.
```

If all four are correct on the client, the problem is on the far side. Move to the **destination** proxy:

```text
   5. INBOUND    istioctl proxy-config cluster deploy/<dest> -n <ns> | grep inbound
                 Is there an inbound|<port>|| cluster?

   6. POLICY     istioctl x describe pod <dest-pod> -n <ns>
                 Effective mTLS mode, and which AuthorizationPolicy selects it.

   7. EVIDENCE   kubectl logs <dest-pod> -c istio-proxy --tail=20
                 Did the request arrive at all?  (section 050)
```

Step 7 is the handover to the next section, and it is also the cheapest step in the list — which is why in a real incident many people run it first and use the configuration walk to explain what the log showed.

## Mapping a symptom to a stage

| Symptom | Most likely stage | Because |
| --- | --- | --- |
| traffic works but no metrics, no policy | **1 — listener** | it was never captured, or it fell to passthrough |
| `404`, flag `NR` | **2 — route** | no virtual host or rule matched |
| the wrong version answers | **2 — route** | a rule matched, but not the one you meant |
| `503`, flag `NC` | **3 — cluster** | the route named a cluster that does not exist |
| `503`, flag `UH` | **4 — endpoint** | the cluster exists with nothing usable behind it |
| `503`, flag `UF` | inbound / mTLS | the connection could not be established at the far end |
| `403` | inbound policy | an `AuthorizationPolicy` on the destination refused |

Those flags come from the access log, which is [section 050](../../section-050/module-01/course.md). Together with this table, they turn a status code into a stage and a stage into one command.

> [!WARNING]
> **Pitfalls across the whole module**
>
> - **Looking only at the client proxy.** `PeerAuthentication` and `AuthorizationPolicy` are enforced inbound. The sender's configuration cannot show you why a policy denied a request.
> - **Dumping everything.** `proxy-config all`, or any subcommand unfiltered, is thousands of lines on a real mesh. Narrow with `--fqdn`, `--port`, `--name` or `--cluster` from the start.
> - **Reading the tabular route output for a match problem.** The `MATCH` column shows `/*` for nearly everything; use `-o json`.
> - **Getting the cluster name slightly wrong.** The exact four-field string, empty fields included, quoted against the shell.
> - **Treating a `HEALTHY` endpoint as a healthy application.** It is Kubernetes readiness, and `OUTLIER CHECK` is a separate, per-proxy verdict.
> - **Forgetting the certificate clock.** A workload certificate is valid for about a day; an expired one explains a mesh-wide failure with no configuration change behind it.
> - **Walking the stages out of order.** Each stage hands a name to the next. Skipping one means guessing at the input to the step you jumped to.

> *The client's configuration explains where a request was sent; only the destination's explains what was allowed to happen when it arrived.*

## Reference

- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — the whole `proxy-config` family with worked output for each subcommand.
- [Envoy config dump](https://www.envoyproxy.io/docs/envoy/latest/operations/admin#get--config_dump) — the raw document every subcommand filters, for fields `istioctl` does not surface.
- [Istio identity and SPIFFE](https://istio.io/latest/docs/concepts/security/#istio-identity) — the SAN format in a workload certificate and how policies match on it.
- [Authorization policy](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — `principals`, `namespaces` and the other source fields evaluated by the inbound RBAC filter.
