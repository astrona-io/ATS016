# Debug A Workload With No Sidecar

Every Istio feature, from routing and retries to mutual TLS, authorization and telemetry, is carried out by the sidecar proxy next to your application. A sidecar proxy (Envoy) is a proxy container that Istio adds to each pod; all inbound and outbound traffic of the pod passes through it. A pod without one does not have fewer features. It is simply not in the mesh, and every policy you write for it does nothing at all.

That is a quiet failure. A control plane problem stops change, and a sync problem stops delivery, but both leave evidence in `istiod`, Istio's control plane. A missing sidecar leaves none, because Kubernetes sees nothing wrong: the pod is `Running`, the Service has endpoints, and requests succeed. This module covers the mechanism that decides whether a pod gets a proxy, and the checklist that finds out why one did not.

The module has four parts. **How Injection Actually Happens** follows a pod through the API server and shows what the injection webhook adds and when. **Labels, Selectors And Precedence** explains which labels decide injection and which one wins when they disagree. **Working The Checklist** covers the remaining checks: pod age, webhook health, revisions and pod spec exclusions. **Fix It And Prove It Joined** removes the cause in the playground and proves the workload joined the mesh. A graded lab follows the fourth part.

## Learning objectives

After this module you can:

- Describe the path that adds a sidecar to a pod, and name what is added.
- Explain why injection cannot be added to a running pod, and what that means for a label change.
- Decide whether a pod has a sidecar, using two independent checks.
- Name the two namespace labels that switch injection on, and say what happens when both are present.
- Explain how the webhook's `namespaceSelector` and `objectSelector` work together with the pod-template label, and which one wins.
- Work the injection checklist in order (namespace label, pod template label, pod age, webhook health, revision, pod spec) and say what each step rules out.
- Predict what injection does during a control plane outage, for each `failurePolicy`.
- Fix a pod-template opt-out and prove the workload joined the mesh in two independent ways.

## Before you start

You need Kubernetes basics: `kubectl` with `patch`, `label` and `rollout restart`, and the fact that a Deployment creates pods from its pod template (`spec.template`). You also need to know that `istioctl proxy-status` lists every proxy connected to `istiod`, and that a workload missing from it usually has no sidecar.

Your playground is a single-node `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` on your PATH. The namespace **`noinject-demo`** is labelled for sidecar injection and runs these workloads:

| Workload | What it is |
| --- | --- |
| `notification-service-v1` | A normal workload in the mesh, behind the Service `notification-service` |
| `reporting-service` | An HTTP echo server (go-httpbin) behind the Service `reporting-service` on port `80`. It is **not in the mesh on purpose**; finding out why is the subject of this module |
| `tester` | A client pod with `curl`. Every test request in this module is sent from here |

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
