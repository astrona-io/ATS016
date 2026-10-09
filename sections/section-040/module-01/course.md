# Read The Proxy Configuration

Sometimes a request does the wrong thing even though everything else checks out. `istioctl analyze` is clean, `istiod` (Istio's control plane) has sent the configuration, and the destination pod has its sidecar proxy. The sidecar proxy (Envoy) is a container that Istio adds to each pod; all inbound and outbound traffic of the pod passes through it. When every outside check passes, the only place left to look is the configuration inside that proxy.

That is less work than it sounds. Envoy handles every request in four stages, always in the same order: listener, route, cluster, endpoint. `istioctl proxy-config` has one subcommand for each stage. Keep one contrast in mind: **`istioctl proxy-status` asks whether the configuration arrived; `istioctl proxy-config` asks what the configuration became.** Every request failure happens at one of the four stages, and knowing which stage a symptom belongs to is most of the diagnosis.

The module has five parts. **Capture And Listeners** shows how traffic reaches the proxy at all and what a listener does with a connection. **Routes** reads the route configuration that turns an HTTP request into a cluster name. **Clusters And Endpoints** reads that cluster name and the pod addresses behind it. **The Receiving Proxy And Its Certificates** moves to the destination pod, where server-side policy and certificates live. **The Four-Stage Walk** joins all four stages into one procedure and maps each symptom to a stage. A graded lab follows the last part.

## Learning objectives

After this module you can:

- Explain how a pod's traffic reaches its sidecar proxy, and why the application needs no change.
- Name Envoy's four request-handling stages and the `istioctl proxy-config` subcommand that shows each.
- Say what ports 15001, 15006, 15021 and 15090 are for.
- Read an Istio cluster name and say what its four fields mean, including an empty subset field.
- Narrow a query with `--fqdn`, `--port`, `--name` and `--cluster` instead of reading a full dump.
- Tell an inbound listener and cluster from an outbound one, and say which side of a connection each belongs to.
- Explain why server-side policy is invisible in the client's configuration.
- Map a symptom (a `404`, a `503`, a policy that appears not to apply) to the stage that most likely produced it.
- Read the certificates a proxy holds and check their validity.

## Before you start

You need Kubernetes basics: namespaces, Deployments, Services, pod labels, `kubectl get` and `kubectl exec`. You also need to know what two Istio resources do. A `VirtualService` tells the sidecar proxies how to route requests for a host. A `DestinationRule` defines what happens to traffic for a host after routing, including **subsets**: named groups of pods selected by labels, such as `version: v1`.

It also helps to know how configuration reaches a proxy. `istiod` sends each proxy its configuration over xDS, the protocol `istiod` uses to push configuration to proxies while they run. The four kinds of configuration are listeners, routes, clusters and endpoints, and `istioctl proxy-status` shows whether each kind arrived. This module reads those same four kinds one by one.

Your playground is a single-node `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` on your PATH. The namespace **`proxycfg-demo`** has sidecar injection switched on, so every pod in it has a sidecar proxy:

| Workload | What it is |
| --- | --- |
| `notification-service-v1` | A Deployment with the label `version: v1`, behind the Service `notification-service` on port `80`. The container listens on port `8084` |
| `tester` | A client pod with `curl`. Every test request in this module is sent from here |

The namespace also holds working routing: a `DestinationRule` that defines the subset `v1`, and a `VirtualService` with a header match and a default route, both pointing at `v1`. Nothing is broken. This module reads a working proxy first, because you cannot recognise a wrong configuration until you know what a correct one looks like. Every command in the parts runs against this playground, and `kubectl` already points at it.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
