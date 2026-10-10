# Read Envoy Access Logs And Response Flags

Every request between two pods in the mesh passes through at least two sidecar proxies. A sidecar proxy (Envoy) is a proxy container that Istio adds to each pod, so that all inbound and outbound traffic of the pod passes through it. Each proxy can write an **access log**: one line per request, with what the proxy did, what the destination answered, how long it took, and a short code that says why the request ended the way it did.

That short code is the **response flag**. `istioctl proxy-config` shows what a proxy is configured to do; the access log shows what it actually did. If you can read the flag, "the service returns errors" becomes "the circuit breaker rejected it", "the route timeout fired" or "the request never left the client pod". You learn that before you open a single YAML file.

This module has five parts. **Turning Logging On, And Scoping It** shows the two ways to switch the access log on and how a `Telemetry` object limits it to one namespace or one workload. **The Anatomy Of A Line** maps the fields of the default log format and the six that answer most questions. **Flags, And Which Proxy Wrote The Line** turns the list of flags into a model and adds the second question: was the line written by the client's proxy or the destination's proxy? **Failures The Client's Proxy Decides** produces a timeout, a circuit breaker rejection and a routing miss on purpose, and a graded lab follows it. **A Denial On The Other Proxy** produces an authorization denial, which only the destination's proxy explains, and a second graded lab follows it.

## Learning objectives

After this module you can:

- Switch on access logging for the whole mesh or for one namespace, and say when to use each.
- Scope logging with a `Telemetry` object, including keeping only failed requests.
- Name the fields of the default access log format and find the response flag.
- Read the response code details and say when they matter more than the flag.
- Map the common flags to their causes, and say what a bare `-` means.
- Tell from a pair of logs whether a request ever reached its destination.
- Produce a timeout, a circuit breaker rejection, a routing miss and an authorization denial on purpose.
- Explain why an authorization denial is only explained on the destination's proxy.
- Count the flags in a window of traffic to see which failure is most common.

## Before you start

You need Kubernetes basics: namespaces, Deployments, Services, and the commands `kubectl logs` and `kubectl exec`. Every pod in the mesh has an `istio-proxy` container next to the application container, and every request in or out goes through it.

You also need a picture of how a proxy handles a request. A request meets a **listener** (the port where the proxy accepts traffic), then a **route** (the rule that picks a destination), then a **cluster** (a named group of destination pods, such as `outbound|80||notification-service.accesslog-demo.svc.cluster.local`), then an **endpoint** (the address of one pod in that group). Several flags name one of these stages directly.

Your playground is one `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` on your PATH. The `demo` profile already switches on access logging for the whole mesh. The namespace **`accesslog-demo`** has sidecar injection switched on and holds these objects:

| Kubernetes name | What it is |
| --- | --- |
| `notification-service` | Service on port `80`, in front of `notification-service-v1` |
| `notification-service-v1` | The application: nginx answering `["EMAIL"]` on any path, and waiting five seconds before it answers on `/slow` |
| `tester` | A client pod with `curl`. Every test request is sent from here |
| `access-logs` | A `Telemetry` object that switches access logging on for this namespace |

Traffic starts healthy. Some parts apply configuration that breaks traffic on purpose: a route timeout, a tight circuit breaker, a route that matches nothing and a deny-all policy. A later step removes each one again, and all of it stays inside this namespace.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
