# Summarise A Workload With describe, Capture A Cluster With bug-report

Astronaut, you are handed the name of one spaceship (a pod) and a complaint. Somewhere on its planet (the namespace) there may be a `VirtualService`, a `DestinationRule`, a `PeerAuthentication` and an `AuthorizationPolicy`, written by four different people at four different times. Only one question matters: *which of them actually apply to this ship, and what do they add up to?*

Answering that by listing objects and reading YAML is slow and easy to get wrong. Whether an object applies depends on selectors, hosts and scope rules, not on what any single file says. This module covers three tools for three versions of that problem. `istioctl x describe pod` is the ship's dossier: every rule that touches one ship, on one page. A raised Envoy log level asks the ship's communications officer (its sidecar proxy) to think out loud about one decision. And `istioctl bug-report` is the black box: an archive of the whole solar system that you can hand to someone else.

## Learning objectives

After this module you can:

- Explain how Istio decides which policies apply to a given workload, including scope precedence for `PeerAuthentication`.
- Run `istioctl x describe pod` and name what each section of its output tells you.
- State a workload's effective mutual TLS mode and the routes that apply to it from `describe` output alone.
- Recognise the two warnings `describe` most often produces, and say what each one silently breaks.
- Explain what Envoy log scopes are and why one scope at `debug` is different from every scope at `debug`.
- Raise one log scope at runtime, read the resulting decision, and put the level back.
- Produce a `bug-report` archive limited to a namespace and a time window, and list what it contains.
- Choose between `describe`, a scoped log level and `bug-report` for a given situation.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels, `kubectl get`, `kubectl logs` and `kubectl exec`.
- **`istioctl analyze`.** It checks that the configuration fits together as a whole. `describe` is the natural next command, once the configuration is coherent and you still do not know what it *does* to one pod.

### What is in your playground

Your playground is a small training solar system: a single-node `kind` cluster with **Istio 1.30.5** already installed (the `demo` profile) and `istioctl` ready to use. It has one planet, the namespace **`describe-demo`**, with sidecar injection switched on. On it you find:

| Ship | Its role |
| --- | --- |
| `notification-service-v1` | A Deployment labelled `version: v1`, behind the Service `notification-service` on port `80` |
| `tester` | Your test ship: a client pod with `curl`. Every test request is sent from here |

Four Istio objects all apply to that one workload:

- a namespace-wide `PeerAuthentication` in `STRICT` mode (the airlock rule: no handshake, no docking);
- a `DestinationRule` defining the subset `v1`;
- a `VirtualService` routing to that subset;
- an `AuthorizationPolicy` that allows only `POST`.

Nothing here is broken. This module is about reading a working system, which is the harder skill.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts of this module

Read the parts in this order:

1. [What describe Resolves For One Workload](./course-01-what-describe-resolves.md): how each object finds its target, scope precedence, how several policies combine into one effective answer, every section of the output, and the warnings at the bottom.
2. [Making A Proxy Narrate One Decision](./course-02-envoy-log-scopes-at-runtime.md): Envoy's administration interface, log scopes, raising `rbac` to `debug` without a restart, reading the authorization verdict, and putting the level back. Your graded mission follows this part.
3. [Capturing A Cluster With bug-report](./course-03-bug-report-and-handover.md): what the archive holds, the flags that keep it usable, how to read one, and why it is sensitive.
4. [Wrap-Up: Mission Debrief](./course-04-wrap-up.md): what you learned, a self-check, and cleaning up.

## Why this matters

"This one service behaves oddly" is one of the most common reports you will get. `describe` is the fastest way to get your bearings on an unfamiliar workload, and it often ends the investigation before you need deeper tools.

When it does not, a scoped log level gives you the proxy's own reasoning for one decision, and `bug-report` freezes the evidence before it disappears. Knowing which of the three to reach for saves you time in the exam and in a real incident.
