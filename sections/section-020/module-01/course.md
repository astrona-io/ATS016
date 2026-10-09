# Debug Conflicting And Shadowed Routes

Astronaut, a header-based route is often the first thing people write in Istio. It is also the first thing that quietly stops working. The YAML is correct, `kubectl apply` is happy, and `istioctl analyze` may say nothing at all. Yet the signal (the request) still lands on the wrong version.

Think of a `VirtualService` as a flight plan: a checklist that says which way a signal flies, based on what it carries. The communications officer on the sending ship (the sidecar proxy) reads that checklist from top to bottom and follows the first line that fits. Two different mistakes break the checklist in the same way:

- **A shadowed rule.** Inside one `VirtualService`, a line high on the checklist catches every signal, so a line below it can never be reached.
- **Two owners for one host.** Two `VirtualService` objects claim the same beacon. Istio merges them into one checklist, in an order nobody chose.

This module takes both apart at the level of what the proxy actually holds. That is where the most useful habit of the course starts: when the proxy's route table disagrees with your YAML, the YAML is not the whole story.

## Learning objectives

After this module you can:

- Describe how a `VirtualService` is turned into Envoy route configuration, and name the parts at each stage.
- Explain how `http` rules are checked, and why a rule with no `match` ends the list.
- Place a catch-all route correctly, and predict what happens when it is placed first.
- Describe what Istio does when two `VirtualService` objects declare the same host, and why the resulting order cannot be trusted.
- Use gateway binding to keep two objects from claiming the same host in the same scope.
- Read the real route order out of a running proxy with `istioctl proxy-config routes`.
- Find a misrouted request by comparing the proxy's route table with the configuration you believe is in force.
- Check a routing fix from both ends: the matched path and the default path.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels and `kubectl exec`.
- **The routing objects.** What a `VirtualService` and a `DestinationRule` are for, and what a subset is. You do not need to have written a routing rule before: this module is about rules going wrong, which teaches the mechanism more sharply than the happy path does.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** already installed (the `demo` profile) and `istioctl` ready to use. It has one planet (namespace), **`conflict-demo`**, with sidecar injection switched on. On it:

| Kubernetes name | What it is |
| --- | --- |
| `notification-service-v1`, `notification-service-v2` | Two ship classes of one app behind one beacon, the Service `notification-service` on port 80. `v1` answers `["EMAIL"]`, `v2` answers `["EMAIL","SMS"]`, so the reply tells you which one answered |
| `tester` | Your test ship, with `curl`. Every test signal is sent from here |
| `DestinationRule` `notification` | Defines the subsets `v1` and `v2` |
| `VirtualService` `notification` and `notification-extra` | Two flight plans for the same beacon, **in conflict on purpose** |

Every command in this module runs against the playground cluster. `kubectl` is already pointed at it.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts, in order

1. [How A VirtualService Becomes A Route Table](./course-01-virtualservice-to-route-table.md)
2. [One Host, Two Owners](./course-02-host-ownership-and-merging.md)
3. [The Route Table Is The Ground Truth](./course-03-reading-the-route-table.md)
4. [Wrap-Up: Mission Debrief](./course-04-wrap-up.md)

## Why this matters

A broken route rarely produces an error. It produces the wrong answer, quietly, and every object involved still looks valid. Learn to read the route table the proxy really holds, and you can explain any "the rule is right and the traffic is wrong" report in a few commands, on the exam and in a real incident.
