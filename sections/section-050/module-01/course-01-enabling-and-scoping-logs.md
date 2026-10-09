# Turning Logging On, And Scoping It

Astronaut, every ship in the mesh has a communications officer: the sidecar proxy (Envoy) that every signal in or out goes through. That officer can keep a flight log, the **access log**, with one line per signal. This part shows the two ways to switch the flight log on, why the scoped way is the better one, and how to keep only the lines you need.

A production install of Istio often leaves access logging off. The reason is volume: one line per request, per proxy, for every request in the mesh.

## Two ways to switch it on

Istio gives you two switches for the flight log. One covers the whole fleet at once; the other is an object you place exactly where you need it.

### Mesh-wide, in the install configuration

The setting `meshConfig.accessLogFile: /dev/stdout` turns logging on for every proxy in the mesh. It lives in the install configuration that `istioctl install` reads:

```yaml
# values passed to istioctl install / the IstioOperator resource
meshConfig:
  accessLogFile: /dev/stdout
  accessLogEncoding: TEXT          # or JSON
  # accessLogFormat: "..."         # override the default format
```

This is simple, and blunt. It switches on logs for hundreds of proxies you may not care about, and changing it means changing the install.

<!-- astrona:playground:renew -->

To see whether `accessLogFile` is set on your own cluster, read the live mesh configuration, which `istiod` keeps in the `istio` ConfigMap:

```sh
kubectl -n istio-system get configmap istio -o yaml
```

Look for `accessLogFile` in the `mesh` section of the output.

### Scoped, with a Telemetry object

The second way is a **`Telemetry`** object. Think of it as the flight log settings: which planets (namespaces) keep a log, and what goes in it. You apply it like any other Kubernetes object, and where you put it decides what it covers:

| Placed in | Covers |
| --- | --- |
| the root namespace (`istio-system`) | the whole mesh |
| an application namespace | every workload in that namespace |
| any namespace, with `spec.selector` | the matching workloads only |

This is the modern approach, and the one to use during an investigation. It belongs to one namespace, you undo it with `kubectl delete`, and it needs no install change and no restart of the control plane.

Your playground was installed with the `demo` profile, which already turns logging on for the whole mesh. So the `Telemetry` object in your playground is not needed there. It is applied so you can see the shape of the object that does the scoping. It looks like this:

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

`envoy` is the built-in provider name for the standard text access log. Providers are defined in `meshConfig.extensionProviders`. The same `Telemetry` object can point at other providers, for example an OpenTelemetry collector, without any workload knowing.

### See it in your playground

Read the scoping object, send one signal from the `tester` ship to the `notification-service` beacon, then read the last line of the tester's flight log:

```sh
kubectl -n accesslog-demo get telemetry access-logs -o yaml | sed -n '/^spec:/,$p'
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -X POST http://notification-service/notify
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
```

You should see something like:

```text
spec:
  accessLogging:
  - providers:
    - name: envoy
[2026-09-27T10:02:11.401Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 14 3 2 "-" "curl/8.4.0" "9c41..." "notification-service" "10.244.0.12:8084" outbound|80||notification-service.accesslog-demo.svc.cluster.local ...
```

One request gave one line, written by the tester's **own** sidecar. That is the `istio-proxy` container of the pod that sent the request, not of the pod that received it. This detail decides which `kubectl logs` command you run, and it becomes a diagnostic tool of its own once you compare both sides of a request.

## Turning it off again, for a smaller scope

A `Telemetry` object can also **switch logging off** for a narrower scope than a wider object switches it on. The field is `disabled: true`:

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

The narrowest scope wins. A workload-scoped object beats a namespace-scoped one, and a namespace-scoped one beats the one in the root namespace. So the realistic production shape is logging switched on for the whole mesh at the root, with a few very busy workloads opted out. That is better than logging switched off everywhere and switched on in a panic during an incident.

## Filtering: logging only what you need

Full logging on a service with thousands of requests a second costs a lot to store. It is also hard to use: a wall of `200` lines hides the few interesting ones. A `Telemetry` object can carry a filter, written in the Common Expression Language (CEL), that the proxy checks for each request:

```yaml
spec:
  accessLogging:
    - providers:
        - name: envoy
      filter:
        expression: "response.code >= 400"
```

Only requests that match the expression get a line. Common forms:

| Expression | Logs |
| --- | --- |
| `response.code >= 400` | errors only |
| `response.code >= 500` | server errors only |
| `has(response.code) && response.code != 200` | anything not a clean success |
| `request.headers['x-debug'] == 'true'` | requests you mark yourself |

The last one is worth knowing. It lets you trace one caller's signals through a mesh where general logging is off: the caller sets a header, and nobody else's logging changes.

There is a trade-off. A filter that keeps only failures takes away the successful requests around them. You lose the normal latency to compare against, and you cannot see that "it worked for this caller and not for that one". During an investigation, log everything for a short time. For normal running, filter.

## The format, and the JSON option

The default format is a fixed order of fields, made to be readable in a terminal. There are two ways to change it:

- **`accessLogEncoding: JSON`** gives the same fields as a JSON (JavaScript Object Notation) object. Use it when another program reads the logs. Each field has a name, so nothing depends on its position.
- **`accessLogFormat`** is a custom template that uses Envoy's command operators (`%RESPONSE_FLAGS%`, `%UPSTREAM_CLUSTER%`, `%DURATION%` and so on).

A custom format is tempting, but resist it. Every runbook and course, this one included, assumes the default field order. If you rearrange it, nobody who learned the standard shape can read your logs. If you need extra fields, add them at the end.

## Where the logs go

`/dev/stdout` means the proxy writes to its container's standard output. That is why `kubectl logs <pod> -c istio-proxy` works. Your cluster's log collector picks up these lines like any other container log, and keeps them for as long as it keeps container logs.

It also means that a deleted pod takes its logs with it, unless something shipped them somewhere first. That is the practical reason to ship logs to a central store. When nobody did, `istioctl bug-report` can still capture the current logs of the whole cluster in one archive.

## Common pitfalls

> [!WARNING]
> - **Expecting logs to be on.** Only some install profiles switch them on. In a production mesh you may have to apply a `Telemetry` object before there is anything to read.
> - **Switching logging on for the whole mesh during an incident.** You get every proxy's traffic at once. Scope it to the namespace or workload you are investigating.
> - **Filtering to errors during an investigation.** Without the successful requests around a failure, you lose the baseline that explains it.
> - **Customising the format.** Every reference assumes the default order. Add fields at the end; do not rearrange them.
> - **Assuming the logs last.** They are container output. A deleted pod takes them with it.
> - **Forgetting `disabled: true` exists.** Silencing one chatty workload is better than switching off logging for a whole namespace.

> *Logging is a volume decision before it is a diagnostic one: scope it with Telemetry, and filter it only once you know what you are looking for.*
