# Debug A Workload With No Sidecar

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-030/module-03/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-03/playground
> astrona destroy ats-016-playground-030-03
> ```

Every Istio feature — routing, retries, mTLS, authorization, telemetry — is implemented by a proxy running next to your application container. A workload without that proxy is not a workload with reduced functionality. It is simply not in the mesh, and every policy you write about it does nothing at all.

That is a quiet failure, and the contrast worth holding is with the failures in the rest of this section: a control plane problem stops *change* and a sync problem stops *delivery*, but both leave evidence in `istiod`. A missing sidecar leaves none, because from Kubernetes' point of view nothing is wrong — the pod is `Running`, the Service has endpoints, requests succeed. This module is the mechanism that decides whether a pod gets a proxy, and the checklist that finds out why one did not.

> No sidecar means no mesh: every policy silently does nothing for that workload.

## How this module is organised

1. **[Part 1 — How Injection Actually Happens](./course-01-the-injection-webhook.md)** — the mutating admission webhook, what it adds to a pod, where the template comes from, and the three consequences of it being an admission-time operation.
2. **[Part 2 — Labels, Selectors And Precedence](./course-02-labels-and-precedence.md)** — the two namespace labels, the pod-template opt-out, the webhook's own selectors, and exactly which setting wins when several apply.
3. **[Part 3 — Working The Checklist](./course-03-working-the-checklist.md)** — pod age, webhook health, revision mismatch and pod-spec exclusions; then fixing a real case and proving the workload joined.

## Learning objectives

After this module you can:

- Describe the admission path that adds a sidecar to a pod, and name what is added.
- Explain why injection cannot be applied retroactively, and what that implies for a label change.
- Determine whether a given pod has a sidecar, using two independent checks.
- Name the two namespace labels that enable injection and say what happens when both are present.
- Explain how the webhook's `namespaceSelector` and the pod-template label interact, and which wins.
- Work the injection checklist in order — namespace label, pod template label, pod age, webhook health, revision, pod spec — and say what each step rules out.
- Predict injection behaviour during a control plane outage for each `failurePolicy`.
- Fix a pod-template opt-out and prove the workload joined the mesh from two directions.

## Before you start

You need to be comfortable with `kubectl`, including `patch` and `rollout restart`. It helps to have read [module 030-02](../module-02/course.md), which ends where this module begins: a workload missing from `istioctl proxy-status` usually has no sidecar.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the namespace **`noinject-demo`**, labelled for injection, containing:

- `notification-service-v1` — a normal meshed workload, behind the Service `notification-service`.
- `reporting-service` — an HTTP service behind the Service `reporting-service`, which is **deliberately not in the mesh**. Finding out why is the module's subject.
- `tester` — a client pod with `curl`.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it.

## Where this fits

This is the third question in the outside-in sequence, and the one that invalidates the other two when the answer is no:

1. Is the control plane healthy? → [030-01](../module-01/course.md)
2. Did configuration reach the proxy? → [030-02](../module-02/course.md)
3. **Is there a proxy at all?** → this module
4. What is the proxy doing with what it received? → [section 040](../../section-040/module-01/course.md)

In practice it is often worth asking question three *first* when a policy appears to have no effect whatsoever. A policy that is partially working is a configuration problem; a policy that does nothing at all, for one workload, is very often a missing sidecar.
