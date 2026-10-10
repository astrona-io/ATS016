# Debug Conflicting And Shadowed Routes

A header-based route is often the first thing people write in Istio, and the first thing that quietly stops working. The YAML is correct, `kubectl apply` succeeds, and yet the request still reaches the wrong version of the service. No error appears anywhere in the request path.

The routing object here is the `VirtualService`: the Istio resource that tells the sidecar proxies how to route requests for a host, as an ordered list of rules. The sidecar proxy (Envoy) is the proxy container Istio adds to each pod; it makes the routing decision for every request the pod sends. Two different mistakes break a `VirtualService` with the same symptom. Inside one object, a rule near the top can match every request, so a rule below it is never checked; that rule is **shadowed**. Across two objects, the same host can be claimed twice, and the proxy then uses only one of them, chosen by an order nobody wrote down.

This module takes both mistakes apart at the level of what the proxy actually holds. It has three parts. **How A VirtualService Becomes A Route Table** shows how `istiod`, Istio's control plane, turns a `VirtualService` into Envoy routes and how the proxy checks them, first match wins. **One Host, Two Owners** shows what Istio does when two objects claim one host, what `istioctl analyze` reports, and how gateway scope decides whether two objects conflict. **The Route Table Is The Ground Truth** reads the real route table from a proxy with `istioctl proxy-config routes`, applies the fix, and proves it on both paths. A graded lab follows the third part.

## Learning objectives

After this module you can:

- Describe how a `VirtualService` is turned into Envoy route configuration, and name the parts at each stage.
- Explain how `http` rules are checked, and why a rule with no `match` ends the list.
- Place a catch-all route correctly, and predict what happens when it is placed first.
- Describe what Istio does when two `VirtualService` objects declare the same host, and why the result cannot be trusted.
- Use gateway binding to keep two objects from claiming the same host in the same scope.
- Read the real route order out of a running proxy with `istioctl proxy-config routes`.
- Find a misrouted request by comparing the proxy's route table with the configuration you believe is in force.
- Check a routing fix from both ends: the matched path and the default path.

## Before you start

You need Kubernetes basics: namespaces, Deployments, Services, pod labels and `kubectl exec`. You also need to know what a `VirtualService` and a `DestinationRule` are for. A `DestinationRule` defines named **subsets** of a Service: groups of pods selected by labels, such as `version: v1`. You do not need to have written a routing rule before. This module is about rules going wrong, which teaches the mechanism more sharply than the working case does.

Your playground is one `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` on your PATH. The namespace **`conflict-demo`** has sidecar injection switched on and holds these objects:

| Kubernetes name | What it is |
| --- | --- |
| `notification-service-v1`, `notification-service-v2` | Two versions of one app behind one Service, `notification-service`, on port `80`. `v1` answers `["EMAIL"]` and `v2` answers `["EMAIL","SMS"]`, so the reply tells you which version answered |
| `tester` | A client pod with `curl`. Every test request is sent from here |
| `DestinationRule` `notification` | Defines the subsets `v1` and `v2` |
| `VirtualService` `notification` and `notification-extra` | Two objects for the same host, **in conflict on purpose** |

Every command in this module runs against the playground cluster, and `kubectl` already points at it.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
