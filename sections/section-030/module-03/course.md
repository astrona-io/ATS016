# Debug A Workload With No Sidecar

Astronaut, every Istio feature (routing, retries, mutual TLS, authorization, telemetry) is carried out by a proxy next to your application: the ship's communications officer. A ship with no communications officer on board is not a ship with fewer features. It is simply not in the mesh, and every policy you write about it does nothing at all.

That is a quiet failure. A control plane problem stops change, and a sync problem stops delivery, but both leave evidence in `istiod`. A missing sidecar leaves none, because Kubernetes sees nothing wrong: the pod is `Running`, the Service has endpoints, and requests succeed. This module is the mechanism that decides whether a pod gets a proxy, and the checklist that finds out why one did not.

> No sidecar means no mesh: every policy silently does nothing for that workload.

## Learning objectives

After this module you can:

- Describe the path that adds a sidecar to a pod, and name what is added.
- Explain why injection cannot be added to a running pod, and what that means for a label change.
- Decide whether a pod has a sidecar, using two independent checks.
- Name the two namespace labels that switch injection on, and say what happens when both are present.
- Explain how the webhook's `namespaceSelector` and the pod-template label work together, and which one wins.
- Work the injection checklist in order (namespace label, pod template label, pod age, webhook health, revision, pod spec) and say what each step rules out.
- Predict what injection does during a control plane outage, for each `failurePolicy`.
- Fix a pod-template opt-out and prove the workload joined the mesh in two independent ways.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** You can use `kubectl`, including `patch`, `label` and `rollout restart`.
- **Pods and Deployments.** A Deployment creates pods from its pod template (`spec.template`).
- **The roll call.** `istioctl proxy-status` lists every proxy connected to `istiod`; a workload missing from it usually has no sidecar.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` ready to use. It has one planet (namespace), **`noinject-demo`**, labelled for injection:

| Ship | What it does |
| --- | --- |
| `notification-service-v1` | A normal meshed app, behind the beacon (Service) `notification-service` |
| `reporting-service` | An HTTP service behind the beacon `reporting-service`. It is **deliberately not in the mesh**; finding out why is this module's subject |
| `tester` | Your test ship: a client pod with `curl` |

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts, in order

1. [How Injection Actually Happens](./course-01-the-injection-webhook.md)
2. [Labels, Selectors And Precedence](./course-02-labels-and-precedence.md)
3. [Working The Checklist](./course-03-working-the-checklist.md)
4. [Fix It And Prove It Joined](./course-04-fix-and-prove.md)
5. [Wrap-Up: Mission Debrief](./course-05-wrap-up.md)

## Why this matters

When a policy has no effect at all on one workload, check for a missing sidecar first. A policy that partly works is a configuration problem. A policy that does nothing for one workload is very often a ship with no communications officer, and no amount of YAML editing will fix that.
