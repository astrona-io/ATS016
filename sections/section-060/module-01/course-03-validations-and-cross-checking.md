# Part 3 — Validations, Badges And Cross-Checking

> Prerequisite: [Part 2 — Reading The Graph](./course-02-reading-the-graph.md). Next: [the module landing page](./course.md), then [module 060-02](../module-02/course.md).

The graph is only half of what Kiali does. The other half reads Istio objects rather than metrics: validating configuration, and reporting how connections were secured. This part covers both, verifies each against the command line underneath it, and ends with the method that keeps Kiali in its proper role.

## Istio Config: the analyzers, with navigation

Kiali's **Istio Config** view lists every Istio object in scope and validates it — using the same analyzers as `istioctl analyze`, reporting the same `IST####` codes ([module 010-01 Part 2](../../section-010/module-01/course-02-reading-analyzer-messages.md)).

Since the findings are identical, the choice between them is about what you are doing:

| Use | When |
| --- | --- |
| **Kiali Istio Config** | you do not know which namespace is at fault; you want to click from a finding to the object; you are showing someone else |
| **`istioctl analyze`** | you already know the namespace; you are in a terminal; you want an exit code for CI |

Kiali's advantages are navigational: a red validation icon on an object, a click through to its YAML, and a mesh-wide view of which namespaces are unhealthy. Its disadvantage is that it is a UI, and a UI cannot fail your build.

> [!TIP]
> **Try it — a broken object, from both directions**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: broken
>   namespace: kiali-demo
> spec:
>   hosts:
>     - notification-service
>   gateways:
>     - does-not-exist
>   http:
>     - route:
>         - destination:
>             host: notification-service
>             subset: nonexistent
> EOF
> istioctl analyze -n kiali-demo
> ```
>
> Expect something like:
>
> ```text
> Error [IST0101] (VirtualService broken.kiali-demo) Referenced gateway not found: "does-not-exist"
> Error [IST0101] (VirtualService broken.kiali-demo) Referenced host+subset in destinationrule not found: "notification-service+nonexistent"
> Warning [IST0109] (VirtualService broken.kiali-demo) The VirtualServices broken.kiali-demo, notification.kiali-demo associated with mesh gateway define the same host notification-service which can lead to undefined behavior.
> ```
>
> Three findings, and in Kiali's Istio Config view the same three appear as a red validation badge on the `broken` object, each linking to the offending field.
>
> Note the third one, which was not the point of the checkpoint: applying a second `VirtualService` for a host that already had one reproduced the host-ownership conflict from [section 020](../../section-020/module-01/course-02-host-ownership-and-merging.md). That is a fair demonstration of how easily it happens — two people, two objects, one host, and the only warning is a `Warning`.

The two tools agreeing is also a useful sanity check in its own right: it confirms Kiali is reading the cluster you think it is.

## The security badge

The padlock on an edge means Kiali found `connection_security_policy="mutual_tls"` on the metrics for that pair. It is the same label [module 050-02 Part 3](../../section-050/module-02/course-03-fixing-and-proving-encryption.md) used to prove a fix, rendered as an icon.

Its value is at scale. During a migration to `STRICT` mTLS, the question "which parts of the mesh are already encrypted" is tedious to answer workload by workload and immediate on a graph with the Security display enabled.

Two cautions, both following from the fact that it is computed from observed traffic:

- **It reports what happened, not what is required.** Under `PERMISSIVE`, some traffic on a path can be mTLS and some plaintext; the badge reflects the mix, not a policy.
- **An edge with no traffic has no badge**, for the same reason it has no edge.

> [!TIP]
> **Try it — the label behind the padlock**
>
> ```sh
> kubectl -n kiali-demo exec deploy/notification-service-v1 -c istio-proxy -- \
>   pilot-agent request GET stats/prometheus | grep istio_requests_total \
>   | grep -o 'connection_security_policy="[^"]*"' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
>    2 connection_security_policy="mutual_tls"
> ```
>
> `mutual_tls` on the **destination's** own metrics, which is where the label is meaningful — the receiving proxy is the one that knows how the connection was secured. A padlock in the UI and this output are the same fact, one rendered and one raw.

## Cross-checking, as a habit

Every visual element in Kiali has a command-line equivalent. Knowing the mapping is what lets you trust the UI in a hurry and verify it when the answer matters:

| Kiali shows | Underneath it is | Check it with |
| --- | --- | --- |
| an edge, with a rate | `sum(rate(istio_requests_total{...}[Nm]))` | `pilot-agent request GET stats/prometheus`, or a Prometheus query |
| edge colour | the `response_code` label distribution | the same metric, grouped by code |
| a padlock | `connection_security_policy="mutual_tls"` | the destination proxy's metrics |
| a red validation badge | an analyzer finding | `istioctl analyze -n <ns>` |
| a workload's health | Kubernetes object state | `kubectl get pods`, `istioctl proxy-status` |
| response time on an edge | `istio_request_duration_milliseconds_bucket` | a `histogram_quantile` query ([module 060-02](../module-02/course.md)) |

The habit worth forming: when Kiali shows something surprising, check the row's right-hand column before acting on it. Not because Kiali is unreliable — it is a faithful renderer — but because the check tells you *which* of the underlying facts is surprising, which is usually the actual finding.

## Cleaning up

> [!TIP]
> **Try it — stopping the load and removing the faults**
>
> ```sh
> kubectl -n kiali-demo exec deploy/tester -- pkill -f 'while true' || true
> kubectl -n kiali-demo delete virtualservice broken notification
> sleep 5
> kubectl -n kiali-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
> istioctl analyze -n kiali-demo
> ```
>
> Expect something like:
>
> ```text
> virtualservice.networking.istio.io "broken" deleted
> virtualservice.networking.istio.io "notification" deleted
> 200
> ✔ No validation issues found when analyzing namespace: kiali-demo.
> ```
>
> Both `VirtualService` objects are gone, so traffic falls back to Istio's default routing for the Service and succeeds — a reminder that a Service with no Istio routing objects at all is a perfectly valid, working configuration.
>
> Prometheus keeps its historical counter values; what changes is the **rate** over the sliding window, so the graph returns to green over the next minute or two rather than instantly. That lag is the same one from [Part 2](./course-02-reading-the-graph.md), now working in your favour.

## The method

```text
   1. Kiali graph          which pair of workloads, how bad, since when
        │                  (set graph type and time window deliberately)
        ▼
   2. Access log, caller   the response flag: which layer failed       (section 050)
        │
        ▼
   3. proxy-config         what the proxy was configured to do         (section 040)
        │
        ▼
   4. istioctl analyze     was the configuration coherent at all       (section 010)
```

Kiali removes the hardest step, which is deciding where to point the other tools. It does not replace any of them, and the moment it is treated as an oracle — "the graph says the notification service is broken" — it starts costing time instead of saving it.

> [!WARNING]
> **Pitfalls with validations and badges**
>
> - **Using Kiali's validations instead of `istioctl analyze`, or the reverse.** They are the same analyzers; choose by what you are doing, not by which you trust.
> - **Trusting the padlock as proof of a `STRICT` policy.** It reflects how observed connections were secured. Under `PERMISSIVE` a path can be partly encrypted.
> - **Expecting a badge on an edge with no traffic.** No traffic, no edge, no badge.
> - **Acting on a surprising panel without checking the data underneath.** The check usually identifies which underlying fact is the real finding.
> - **Leaving fault injection in place.** A `VirtualService` aborting 30% of requests keeps doing so after you stop looking at the graph.
> - **Leaving a load generator running.** It is a background process inside a pod; `pkill` it, or destroy the playground.

> *Every pixel in Kiali has a command behind it — knowing which one is what turns a dashboard into evidence.*

## Reference

- [Kiali validations](https://kiali.io/docs/features/validations/) — the checks it runs and how they map to Istio's analyzer codes.
- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — the `IST####` catalogue both tools report against.
- [Kiali security display](https://kiali.io/docs/features/security/) — what the padlock is computed from.
- [Istio standard metrics](https://istio.io/latest/docs/reference/config/metrics/) — `connection_security_policy`, `response_code` and the duration histogram behind each display option.
