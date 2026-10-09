# Find Configuration Errors With istioctl analyze

Astronaut, imagine filing a flight plan at the registry office. The clerk checks that every box on the form is filled in correctly, stamps it, and files it. Nobody checks whether the ship class named on the form was ever built. Your flight plan is "valid", and your signals still go nowhere.

That is exactly what happens in Istio. A `VirtualService` (the flight plan for signals) that routes to a subset nobody defined applies cleanly. `kubectl get` lists it, and `kubectl describe` shows nothing worth reading. The only visible symptom is that requests fail with `503`, several layers away from the object that caused it.

This module is about that gap, and about the tool that closes it. Keep one sentence in mind: **`kubectl apply` checks one document at a time, and `istioctl analyze` checks a whole configuration set.** The analyzer is the pre-flight inspector: it reads every form together, the way `istiod` (mission control) does, and finds the ones that point at nothing.

## Learning objectives

After this module you can:

- Describe the stages a `kubectl apply` of an Istio resource passes through, and name which stage rejects what.
- Explain why a reference from one object to another cannot be checked when the object is applied, and what that means for your own manifests.
- Run `istioctl analyze` against a namespace, the whole mesh, and a file that has not been applied yet.
- Read an analyzer message and name its severity, its `IST####` code, and the object it blames.
- Explain why a `Warning` is often the real cause of a "my configuration does nothing" report.
- Use `--failure-threshold` and the command's exit code to make analysis a build gate.
- Choose between `istioctl validate` and `istioctl analyze` for a given situation, and state what each cannot see.
- Fix an analyzer `Error` and prove the fix with both a clean analyze run and real traffic.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels, `kubectl get`, `kubectl apply` and `kubectl exec`.
- **What a `VirtualService` and a `DestinationRule` are for.** This module does not teach routing. It teaches how to find out that your routing is broken.

### What is in your playground

Your playground is a small training solar system: a single-node `kind` cluster with **Istio 1.30.5** already installed (the `demo` profile) and `istioctl` ready to use. It has one planet, the namespace **`analyze-demo`**, with sidecar injection switched on. On it you find:

| Ship | Its role |
| --- | --- |
| `notification-service-v1` | A Deployment labelled `version: v1`, behind the Service `notification-service` on port `80`. It answers `["EMAIL"]` |
| `tester` | Your test ship: a client pod with `curl`. Every test request is sent from here |

There is also a `DestinationRule` and a `VirtualService` that **are already broken on purpose**. Finding out how is the subject of this module, so do not read the playground's manifest files until you have run the analyzer yourself.

Every command in every part runs against the playground cluster. `kubectl` is already pointed at it.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts of this module

Read the parts in this order:

1. [What The API Server Checks, And What It Cannot](./course-01-admission-and-the-analysis-gap.md): the stages a `kubectl apply` passes through, why the validating webhook cannot catch a missing subset, and what an analyzer is.
2. [Reading What The Analyzer Says](./course-02-reading-analyzer-messages.md): severity, `IST####` code and blamed object, the codes worth knowing by heart, JSON output, and the exit code that turns analysis into a build gate.
3. [Choosing The Right Analysis Source](./course-03-analysis-sources-and-the-fix-loop.md): the cluster, a file on top of the cluster, or a file alone; `validate` against `analyze`; and fixing one thing at a time, then proving it twice. Your graded mission follows this part.
4. [Wrap-Up: Mission Debrief](./course-04-wrap-up.md): what you learned, a self-check, and cleaning up.

## Why this matters

`istioctl analyze` is the cheapest question you can ask about a broken mesh. It takes two seconds and names the object, the field and the value that do not resolve. Ask it first, and you will not spend an hour reading thousands of lines of proxy configuration to find a typo.

It also keeps you honest in the other direction. A clean analyze run proves the configuration is coherent. It does not prove that the configuration reached the proxies, or that requests succeed. A clean report moves the investigation on; it does not end it.
