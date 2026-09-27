# Check Control Plane Health

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-030/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-01/playground
> astrona destroy ats-016-playground-030-01
> ```

When a mesh misbehaves, the instinct is to look at the workload. Often the right place to look is `istiod`, and the reason people look there last is that a broken control plane does not look like an outage. Traffic keeps flowing. Dashboards stay green. What stops is *change* — and nothing reports that change has stopped.

The contrast that sharpens the boundary: a **data plane** failure shows up as failed requests, immediately, on the request path. A **control plane** failure shows up as an absence — configuration that never takes effect, pods that never become ready, certificates that eventually expire. This module takes `istiod` apart into the four jobs it does, shows how each fails on its own, and gives you the instruments that say which one is in trouble.

> istiod is a config server and a CA: when it is down, existing traffic keeps flowing but nothing new can change.

## How this module is organised

1. **[Part 1 — Four Jobs In One Process](./course-01-the-four-jobs-of-istiod.md)** — the xDS server, the certificate authority, the injection webhook and the validation webhook; what each failure looks like from the outside, and the certificate clock that makes one of them a delayed fuse.
2. **[Part 2 — The Instruments](./course-02-instruments-logs-and-metrics.md)** — readiness against liveness, what a healthy push log narrates, the metrics endpoint on 15014, how to decode the `pilot_*` names, and reading resource pressure.
3. **[Part 3 — Outage Anatomy And Rejected Configuration](./course-03-outage-anatomy-and-rejects.md)** — taking the control plane down and watching which half of the mesh notices, why new pods are blocked rather than unmeshed, and the failure where `kubectl apply` succeeds and nothing is ever pushed.

## Learning objectives

After this module you can:

- Name the four jobs `istiod` performs and describe how the mesh degrades when each one fails.
- Explain why running proxies keep serving traffic without a control plane, and what ends that grace period.
- Distinguish `istiod`'s readiness from its health, and say what a climbing restart count on a `Running` pod means.
- Query `istiod`'s metrics endpoint and interpret `pilot_xds_pushes`, `pilot_xds_push_errors`, `pilot_total_xds_rejects` and `pilot_proxy_convergence_time`.
- Explain why a counter that has never incremented is absent rather than zero.
- Predict what happens to pod creation during a control plane outage, for each webhook `failurePolicy`.
- Explain where a rejected configuration becomes visible, given that `kubectl apply` reported success.
- Recognise the slow version of the same failure — a control plane under resource pressure.

## Before you start

You need to be comfortable with `kubectl`, including `logs`, `exec` and `scale`. No Istio object is written in this module — the subject is the component that serves them.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the injected namespace **`cphealth-demo`** containing `notification-service-v1` behind a Service on port 80, plus a `tester` client pod with `curl`.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it. Part 3 deliberately takes the control plane down — safe here because the environment is throwaway, and something that would stop every team's deployments on a shared cluster.

## Where this fits

This module sits at the top of the outside-in sequence, one level above where [module 010-01](../../section-010/module-01/course.md) started:

1. Is the **control plane** healthy enough to serve configuration at all? → this module
2. Did the configuration **reach** each proxy? → [`istioctl proxy-status`](../module-02/course.md)
3. Is the workload even **in the mesh**? → [sidecar injection](../module-03/course.md)
4. What is the proxy **doing** with what it received? → [`istioctl proxy-config`](../../section-040/module-01/course.md)

Taking them in order stops you debugging a route that was never pushed, or a policy on a pod with no sidecar to enforce it.
