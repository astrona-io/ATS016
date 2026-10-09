# Read The Proxy Configuration

Astronaut, picture a signal that does the wrong thing even though everything looks right. The configuration is coherent, mission control (`istiod`) delivered it, and the spaceship (pod) has its communications officer (the sidecar proxy) on board. There is only one place left to look: inside the officer's own orders book.

That sounds harder than it is. The proxy, Envoy, handles every request in four stages, always in the same order, and `istioctl proxy-config` has one subcommand for each stage. Keep this contrast in mind: **`proxy-status` asks whether the orders arrived; `proxy-config` asks what the orders became.** Every request failure lives at exactly one of the four stages, and knowing which stage a symptom belongs to is most of the diagnosis.

> Listener, route, cluster, endpoint: every request failure lives at exactly one of those four steps.

## Learning objectives

After this module you can:

- Explain how a pod's traffic reaches its sidecar, and why the application needs no change.
- Name Envoy's four request-handling stages and the `istioctl proxy-config` subcommand that shows each.
- Say what ports 15001, 15006, 15021 and 15090 are for.
- Read an Istio cluster name and say what its four fields mean, including an empty subset field.
- Narrow a query with `--fqdn`, `--port`, `--name` and `--cluster` instead of reading a full dump.
- Tell an inbound listener and cluster from an outbound one, and explain which side of a connection each belongs to.
- Explain why server-side policy is invisible in the client's configuration.
- Map a symptom (a `404`, a `503`, a policy that appears not to apply) onto the stage that most likely produced it.
- Inspect the certificates a proxy is holding and read their validity.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels, `kubectl get` and `kubectl exec`.
- **What a `VirtualService` and a `DestinationRule` do.** A `VirtualService` is the flight plan that says where a signal goes. A `DestinationRule` gives docking instructions for one beacon (Service), including its subsets: ship classes of the same model, such as `v1` and `v2`.
- **How orders reach a proxy.** `istiod` sends each proxy its configuration over a stream called xDS. The four kinds of orders are listeners, routes, clusters and endpoints, and `istioctl proxy-status` shows whether each kind arrived. This module reads those same four kinds one by one.

### What is in your playground

Your playground is a small training solar system: a single-node `kind` cluster with **Istio 1.30.5** already installed (the `demo` profile), and `istioctl` ready to use. It has one planet (namespace), **`proxycfg-demo`**, with injection switched on, so every ship on it has a communications officer:

| Ship | Its role |
| --- | --- |
| `notification-service-v1` | The app, labelled `version: v1`, behind the beacon `notification-service` on port 80. The container listens on port 8084 |
| `tester` | Your test ship, with `curl`. Every test signal is sent from here |

The playground also holds working routing: a `DestinationRule` that defines subset `v1`, and a `VirtualService` with a header match and a default route, both pointing at `v1`.

Nothing is broken. This module reads a working proxy, because you cannot recognise a wrong configuration until you know what a right one looks like. Every command in every part runs against this playground, and `kubectl` already points at it.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts, in order

1. [Capture And Listeners](./course-01-capture-and-listeners.md): how traffic gets into the proxy at all, ports 15001 and 15006, and what a listener does with a connection.
2. [Routes](./course-02-routes.md): route configurations named by port, how the `Host` header picks a virtual host, and why the table output hides what you need.
3. [Clusters And Endpoints](./course-03-clusters-and-endpoints.md): the four-field cluster name, discovery types, endpoint lists, and `HEALTHY` against `OUTLIER CHECK`.
4. [The Receiving Proxy And Its Certificates](./course-04-the-receiving-proxy-and-certificates.md): the destination's configuration, where server-side policy lives, and the certificates a proxy holds.
5. [The Four-Stage Walk](./course-05-the-four-stage-walk.md): the whole chain as one procedure, a symptom-to-stage map, and your graded mission.
6. [Wrap-Up: Mission Debrief](./course-06-wrap-up.md): what you learned, a self-check, and cleaning up.

## Why this matters

When a signal goes wrong and every object looks correct, the proxy's own configuration is the ground truth. Reading it stage by stage turns "Istio is ignoring my rule" into a precise finding: no listener, no matching route, a cluster that does not exist, or a cluster with nothing behind it. Each of those findings points at one object to fix.
