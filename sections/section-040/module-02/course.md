# Debug A 503 Caused By A Missing Subset

Astronaut, `503 Service Unavailable` is the most common failure in an Istio mesh, and on its own it says almost nothing. It can mean the app crashed, or that nothing was ever running. In a mesh it usually means something else: the communications officer (the sidecar proxy) had nowhere to send the signal, because its flight plan names a ship class nobody built.

Hold on to this contrast: a `503` from your **app** and a `503` from the **proxy in front of it** look exactly the same to the client, yet they need completely different investigations. One question separates them, and it takes one command. This module works through one case from start to finish, a `VirtualService` that routes to a subset no `DestinationRule` defines, but the method is the point, and it works for every `503` you will meet.

> A route to a subset with no DestinationRule names a cluster that does not exist, and a proxy with nowhere to send a request answers 503.

## Learning objectives

After this module you can:

- Read a `503` as a statement about the proxy rather than about the app, and prove which one answered.
- Find the response flag in an Envoy access log line and say what `NC`, `UH`, `NR`, `UF`, `UC` and `-` each point at.
- Explain why a failing request leaves no trace on the destination proxy.
- Follow the route, cluster and endpoint chain to the exact link that is missing.
- Tell a missing cluster from an empty one, and name the flag that separates them.
- Decide whether to change the route or define the missing subset, and explain the choice.
- Prove a fix with traffic, the proxy's own configuration, and the analyzer.
- Recognise a Service port with no declared protocol as a second cause of the same symptom.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels, `kubectl logs` and `kubectl exec`.
- **The proxy's four stages.** Envoy handles a request as listener, then route, then cluster, then endpoint, and `istioctl proxy-config` has one subcommand for each.
- **Cluster names.** Istio names a cluster `direction|port|subset|fqdn`, for example `outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local`. A subset cluster exists only if a `DestinationRule` defines that subset.

### What is in your playground

Your playground is a small training solar system: a single-node `kind` cluster with **Istio 1.30.5** already installed (the `demo` profile, which turns access logging on), and `istioctl` ready to use. It has one planet (namespace), **`fivezerothree-demo`**, with injection switched on:

| Ship | Its role |
| --- | --- |
| `notification-service-v1` | The app, labelled `version: v1`, behind the beacon `notification-service` on port 80 |
| `tester` | Your test ship, with `curl`. Every test signal is sent from here |

The planet also holds a `DestinationRule` and a `VirtualService` that are **already broken**, in exactly the way this module diagnoses. Work the chain before you read the files in `playground/manifests/`. Every command in every part runs against this playground, and `kubectl` already points at it.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts, in order

1. [Who Answered With 503](./course-01-who-answered-with-503.md): a proxy failure against an app failure, the response flag, and what each flag in the `503` family points at.
2. [Walking The Chain](./course-02-walking-the-chain.md): the analyzer's fast path, then route, cluster and endpoint by hand, and the two kinds of empty answer.
3. [Choosing And Proving The Fix](./course-03-choosing-and-proving-the-fix.md): which end of a dangling reference to change, proving the fix three ways, and your graded mission.
4. [The Other Cause: An Undeclared Port](./course-04-the-other-cause-an-undeclared-port.md): a Service port with no declared protocol, which produces the same symptom from a different place.
5. [Wrap-Up: Mission Debrief](./course-05-wrap-up.md): what you learned, a self-check, and cleaning up.

## Why this matters

The method in this module is short and works for any `503`: read the response flag on the client proxy, check whether the destination saw the request, run the analyzer, walk the chain, and fix the end that matches reality. Learn it on one clear case, and the next `503` takes minutes instead of an afternoon.
