# Turning Logging On, And Scoping It

Before you can read an access log, a proxy has to write one. The access log is a record that the sidecar proxy (Envoy) writes, with one line per request that passes through it. Many production installs of Istio leave it off, because the volume is large: one line per request, per proxy, for every request in the mesh. This part shows the two ways to switch the access log on, why the scoped way is the better one during an investigation, and how to keep only the lines you need.

## Two ways to switch it on

Istio gives you two switches for the access log. One is part of the install and covers the whole mesh at once. The other is a Kubernetes object that you place exactly where you need it.

### Mesh-wide, in the install configuration

The setting `meshConfig.accessLogFile: /dev/stdout` turns logging on for every proxy in the mesh. `meshConfig` is the mesh-wide configuration that `istioctl install` reads and that `istiod`, Istio's control plane, sends to every proxy:

```yaml
# values passed to istioctl install / the IstioOperator resource
meshConfig:
  accessLogFile: /dev/stdout
  accessLogEncoding: TEXT          # or JSON
  # accessLogFormat: "..."         # override the default format
```

This switch is simple but blunt. It turns on logs for hundreds of proxies you may not care about, and changing it means changing the install.

To see whether `accessLogFile` is set on your own cluster, read the live mesh configuration. `istiod` keeps it in the `istio` ConfigMap in the `istio-system` namespace:

<!-- astrona:playground:renew -->

```sh
kubectl -n istio-system get configmap istio -o yaml
```

Look for `accessLogFile` in the `mesh` section of the output. The playground was installed with the `demo` profile, so the setting is there.

### Scoped, with a Telemetry object

The second way is a **`Telemetry`** object: an Istio resource that configures access logs, metrics and tracing for the proxies it covers. You apply it like any other Kubernetes object, and the namespace you put it in decides what it covers:

| Placed in | Covers |
| --- | --- |
| the root namespace (`istio-system`) | the whole mesh |
| an application namespace | every workload in that namespace |
| any namespace, with `spec.selector` | the matching workloads only |

This is the approach to use during an investigation. It belongs to one namespace, you undo it with `kubectl delete`, and it needs no install change and no restart of `istiod`.

The `demo` profile already logs for the whole mesh, so the playground does not need a `Telemetry` object. It has one anyway, called `access-logs`, so you can see the object that does the scoping in a real install. Read its `spec`, send one request from the `tester` pod to the `notification-service` Service, and read the last line of the `tester` pod's proxy log:

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

`envoy` is the name of the built-in provider for the standard text access log. Providers are defined in `meshConfig.extensionProviders`, and the same `Telemetry` object can point at another provider, such as an OpenTelemetry collector, without any change to the workloads.

The one request produced one line, written by the `tester` pod's **own** sidecar proxy. That is the `istio-proxy` container of the pod that sent the request, not of the pod that received it. This detail decides which `kubectl logs` command you run. It also becomes a diagnostic tool of its own once you compare both sides of a request.

## Turning it off again, for a smaller scope

A `Telemetry` object can also switch logging **off** for a narrower scope than a wider object switches it on. The field is `disabled: true`. This fragment of a `spec` turns logging off for the workloads with the label `app: very-chatty-service`:

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

The narrowest scope wins. A `Telemetry` object for selected workloads beats one for the namespace, and one for the namespace beats the one in the root namespace. So a common production setup is logging switched on for the whole mesh at the root, with a few very busy workloads switched off. That is better than logging switched off everywhere and switched on in a hurry during an incident.

## Filtering: logging only what you need

Full logging on a service with thousands of requests a second costs a lot to store. It is also hard to use, because a wall of `200` lines hides the few interesting ones. So a `Telemetry` object can carry a filter, written in the Common Expression Language (CEL), that the proxy checks for each request:

```yaml
spec:
  accessLogging:
    - providers:
        - name: envoy
      filter:
        expression: "response.code >= 400"
```

The proxy writes a line only for requests that match the expression. Some common forms are:

| Expression | Logs |
| --- | --- |
| `response.code >= 400` | errors only |
| `response.code >= 500` | server errors only |
| `has(response.code) && response.code != 200` | anything that is not a clean success |
| `request.headers['x-debug'] == 'true'` | requests you mark yourself |

The last one is worth knowing. It lets you follow one caller's requests through a mesh where general logging is off: the caller sets a header, and nobody else's logging changes.

A filter has a cost, though. A filter that keeps only failures also removes the successful requests around them. You lose the normal latency to compare against, and you cannot see that a call worked for one caller and not for another. During an investigation, log everything for a short time; for normal running, filter.

## The format, and the JSON option

The default format is a fixed order of fields, made to be read in a terminal. There are two ways to change it. `accessLogEncoding: JSON` gives the same fields as a JSON (JavaScript Object Notation) object, so each field has a name and nothing depends on its position; use it when another program reads the logs. `accessLogFormat` is a custom template built from Envoy's command operators, such as `%RESPONSE_FLAGS%`, `%UPSTREAM_CLUSTER%` and `%DURATION%`.

A custom format is tempting, but think twice. Runbooks, tools and this course all assume the default field order. If you rearrange it, people who learned the standard order cannot read your logs. If you need extra fields, add them at the end.

## Where the logs go

`/dev/stdout` means the proxy writes to its container's standard output. That is why `kubectl logs <pod> -c istio-proxy` shows the lines. The cluster's log collector picks them up like any other container log and keeps them as long as it keeps container logs.

It also means that a deleted pod takes its logs with it, unless something sent them somewhere first. That is the practical reason to send logs to a central store. When nobody did, `istioctl bug-report` can still capture the current logs of the whole cluster in one archive.

You now know how to switch the access log on for the whole mesh or for one namespace, how to switch it off for one busy workload, and how to filter it. You also know that each line comes from the proxy of one pod, and that it lives only as long as the pod. The next question is how to read one of those lines, because none of its twenty or so fields has a label.

## Common pitfalls

> [!WARNING]
> - **Expecting logs to be on.** Only some install profiles switch them on. In a production mesh you may have to apply a `Telemetry` object before there is anything to read.
> - **Switching logging on for the whole mesh during an incident.** You get every proxy's traffic at once. Scope it to the namespace or workload you are investigating.
> - **Filtering to errors during an investigation.** Without the successful requests around a failure, you lose the baseline that explains it.
> - **Customising the format.** Every reference assumes the default order. Add fields at the end; do not rearrange them.
> - **Assuming the logs last.** They are container output. A deleted pod takes them with it.
> - **Forgetting `disabled: true`.** Switching off one busy workload is better than switching off logging for a whole namespace.
