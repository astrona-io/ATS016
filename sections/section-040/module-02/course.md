# Debug A 503 Caused By A Missing Subset

`503 Service Unavailable` is one of the most common failures in an Istio mesh, and on its own it says almost nothing. It can mean the application crashed, or that no pod was ever running. In a mesh it often means something else: the sidecar proxy had nowhere to send the request, because its route names a destination that does not exist.

A `503` from your **application** and a `503` from the **proxy in front of it** look exactly the same to the client, yet they need completely different investigations. One question separates them, and it takes one command. This module works through one case from start to finish: a `VirtualService` that routes to a subset no `DestinationRule` defines. The method is the real goal, because it works for every `503`.

The module has four parts. **Who Answered With 503** reads the Envoy access log to find out whether a proxy or the application produced the status code, and what the response flag says. **Walking The Chain** confirms the finding with `istioctl analyze`, then follows the route, cluster and endpoint stages by hand to the missing link. **Choosing And Proving The Fix** decides which end of the broken reference to change and proves the fix three ways; a graded lab follows it. **Declaring The Port Protocol** shows a second cause of "my routing rule does nothing": a Service port whose protocol Istio does not treat as HTTP. A second graded lab follows that part.

## Learning objectives

After this module you can:

- Read a `503` as a statement about the proxy rather than the application, and prove which one answered.
- Find the response flag in an Envoy access log line and say what `NC`, `UH`, `NR`, `UF`, `UC` and `-` each point at.
- Explain why a failing request leaves no trace in the destination proxy's log.
- Follow the route, cluster and endpoint chain to the exact link that is missing.
- Tell a missing cluster from an empty one, and name the flag that separates them.
- Decide whether to change the route or define the missing subset, and explain the choice.
- Prove a fix with a real request, the proxy's own configuration, and the analyzer.
- Explain how Istio decides a Service port's protocol, and fix a port whose protocol stops HTTP routing.

## Before you start

You need Kubernetes basics: namespaces, Deployments, Services, pod labels, `kubectl logs` and `kubectl exec`. You also need the four stages of the sidecar proxy (Envoy), the proxy container Istio adds to each pod. Envoy handles a request as listener, then route, then cluster, then endpoint, and `istioctl proxy-config` has one subcommand for each.

You also need to read cluster names. Istio names a cluster `direction|port|subset|fqdn`, for example `outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local`. A subset is a named group of pods selected by labels in a `DestinationRule`, and a subset cluster exists only if a `DestinationRule` defines that subset.

Your playground is a single-node `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, which turns on Envoy access logging, and `istioctl` on your PATH. The namespace **`fivezerothree-demo`** has sidecar injection switched on and runs these workloads:

| Workload | What it is |
| --- | --- |
| `notification-service-v1` | A Deployment with the label `version: v1`, behind the Service `notification-service` on port `80` |
| `tester` | A client pod with `curl`. Every test request in this module is sent from here |

The namespace also holds a `DestinationRule` and a `VirtualService` that are **broken on purpose**, in exactly the way this module diagnoses. Follow the chain before you read their YAML. Every command in the parts runs against this playground, and `kubectl` already points at it.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
