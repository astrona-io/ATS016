# Part 1 — Turning Logging On, And Scoping It

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — The Anatomy Of A Line](./course-02-anatomy-of-a-log-line.md).

Access logging is off by default in a production-oriented Istio install, and the reason is volume: one line per request, per proxy, for every request in the mesh. This part covers the two ways to turn it on, why the scoped one is the modern answer, and the filtering that makes it affordable on a busy service.

## Two mechanisms

**Mesh-wide, in the install configuration.** `meshConfig.accessLogFile: /dev/stdout` turns it on for every proxy in the mesh:

```yaml
# values passed to istioctl install / the IstioOperator resource
meshConfig:
  accessLogFile: /dev/stdout
  accessLogEncoding: TEXT          # or JSON
  # accessLogFormat: "..."         # override the default format
```

Simple, and blunt. It applies to several hundred proxies you did not want logs from, and changing it means touching the install.

**Scoped, with a `Telemetry` resource.** A Kubernetes object, applied like any other, whose scope is decided by where you put it:

| Placed in | Covers |
| --- | --- |
| the root namespace (`istio-system`) | the whole mesh |
| an application namespace | every workload in that namespace |
| any namespace, with `spec.selector` | the matching workloads only |

This is the modern approach and the one to reach for when investigating: it is namespaced, revertible with `kubectl delete`, and needs no install change or control plane restart.

The `demo` profile used by this playground already enables logging mesh-wide, so the `Telemetry` object here is redundant — it is present so you can see the shape of the object that does the scoping:

```yaml
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-logs
  namespace: accesslog-demo
spec:
  accessLogging:
    - providers:
        - name: envoy
```

`envoy` is the built-in provider name for the standard text access log. Providers are defined in `meshConfig.extensionProviders`, and the same `Telemetry` object can point at others — an OpenTelemetry collector, for instance — without any workload knowing.

> [!TIP]
> **Try it — the scoping object, and that logging works**
>
> ```sh
> kubectl -n accesslog-demo get telemetry access-logs -o yaml | sed -n '/^spec:/,$p'
> kubectl -n accesslog-demo exec deploy/tester -- \
>   curl -s -o /dev/null -X POST http://notification-service/notify
> kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
> ```
>
> Expect something like:
>
> ```text
> spec:
>   accessLogging:
>   - providers:
>     - name: envoy
> [2026-09-27T10:02:11.401Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 14 3 2 "-" "curl/8.4.0" "9c41..." "notification-service" "10.244.0.12:8084" outbound|80||notification-service.accesslog-demo.svc.cluster.local ...
> ```
>
> One request, one line, written by `tester`'s **own** sidecar — the `istio-proxy` container of the pod that sent the request, not of the pod that received it. That detail decides which `kubectl logs` command you run, and [Part 3](./course-03-flags-and-which-proxy.md) makes it a diagnostic in its own right.

## Turning it off again, per scope

A `Telemetry` object can also **disable** logging for a narrower scope than an enclosing one enables. The field is `disabled: true`:

```yaml
spec:
  selector:
    matchLabels:
      app: very-chatty-service
  accessLogging:
    - providers:
        - name: envoy
      disabled: true
```

Resolution is narrowest-wins, in the same spirit as the policy precedence from [module 010-02 Part 1](../../section-010/module-02/course-01-what-describe-resolves.md): a workload-scoped object overrides a namespace-scoped one, which overrides the root-namespace one. So the realistic production shape is mesh-wide logging enabled at the root, with a handful of high-volume workloads opted out — rather than logging disabled everywhere and switched on in a panic.

## Filtering: logging only what you need

Full logging on a service handling thousands of requests a second is expensive in log pipeline cost and largely useless — a wall of `200`s in which the interesting lines are invisible. `Telemetry` supports a CEL filter expression evaluated per request:

```yaml
spec:
  accessLogging:
    - providers:
        - name: envoy
      filter:
        expression: "response.code >= 400"
```

Only requests matching the expression are logged. Common forms:

| Expression | Logs |
| --- | --- |
| `response.code >= 400` | errors only |
| `response.code >= 500` | server errors only |
| `has(response.code) && response.code != 200` | anything not a clean success |
| `request.headers['x-debug'] == 'true'` | requests you mark yourself |

The last one is worth knowing: it gives you a way to trace a specific caller's traffic through a mesh where general logging is off, by setting a header rather than changing configuration for everyone.

There is a trade-off to state plainly. A filter that keeps only failures means you cannot compare a failure against the successful requests around it — no baseline latency, no "it worked for this caller and not that one". For an investigation, log everything for a short window; for steady state, filter.

## Format, and the JSON option

The default format is a fixed field order designed to be readable in a terminal, and [Part 2](./course-02-anatomy-of-a-log-line.md) takes it apart. Two ways to change it:

- **`accessLogEncoding: JSON`** — the same fields as a JSON object, which is what you want when something downstream parses the logs. Field names become explicit, so nothing depends on position.
- **`accessLogFormat`** — a custom template using Envoy's command operators (`%RESPONSE_FLAGS%`, `%UPSTREAM_CLUSTER%`, `%DURATION%`, and so on).

A custom format is tempting and worth resisting for one reason: every runbook, blog post and course — including this one — assumes the default field order. Changing it makes your logs unrecognisable to everyone who has learned the standard shape. If you need extra fields, add them at the end rather than rearranging.

## Where the logs go

`/dev/stdout` means the proxy writes to its container's standard output, which is what makes `kubectl logs <pod> -c istio-proxy` work. Everything else follows from that: your cluster's log collector picks them up like any other container log, retention is whatever it is for container logs, and a pod that is deleted takes its logs with it unless something shipped them.

That last point is the practical argument for shipping logs somewhere, and the reason `istioctl bug-report` ([module 010-02 Part 3](../../section-010/module-02/course-03-bug-report-and-handover.md)) exists for the case where they were not.

> [!WARNING]
> **Pitfalls in enabling and scoping**
>
> - **Expecting logs to be on.** Only some install profiles enable them. In a production mesh you may have to apply a `Telemetry` object before there is anything to read.
> - **Enabling mesh-wide during an incident.** You get every proxy's traffic at once. Scope to the namespace or workload you are investigating.
> - **Filtering to errors during an investigation.** Without the surrounding successes you lose the baseline that makes a failure interpretable.
> - **Customising the format.** Every reference, including this module, assumes the default order. Append fields; do not rearrange them.
> - **Assuming the logs persist.** They are container stdout. A deleted pod takes them with it.
> - **Forgetting `disabled: true` exists.** Silencing one chatty workload is better than disabling logging for a namespace to make room for it.

> *Logging is a volume decision before it is a diagnostic one — scope it with Telemetry, and filter it only once you know what you are looking for.*

## Reference

- [Telemetry API — access logging](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — enabling, scoping, disabling and filtering, with the CEL expression syntax.
- [Telemetry resource reference](https://istio.io/latest/docs/reference/config/telemetry/) — `providers`, `filter`, `disabled` and the scope resolution rules.
- [Envoy access log configuration](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage) — the command operators available in a custom format.
- `kubectl -n istio-system get configmap istio -o yaml` — the live `meshConfig` on your own cluster, including whether `accessLogFile` is set.
