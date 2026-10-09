# Check Control Plane Health

Astronaut, when something in the mesh goes wrong, you usually look at the ship that is failing. Often the better place to look is mission control: `istiod`, the control plane that sends every communications officer (sidecar proxy) their orders. People look there last, because a broken control plane does not look like an outage. Signals keep flowing and dashboards stay green. What stops is *change*, and nothing reports that change has stopped.

Here is the difference to hold on to. A **data plane** failure (a problem in the proxies that carry the requests) shows up at once, as failed requests. A **control plane** failure shows up as something missing: configuration that never takes effect, pods that never become ready, badges (certificates) that quietly expire. This module splits `istiod` into the four jobs it does, shows how each one fails, and gives you the tools that say which job is in trouble.

> `istiod` is a configuration server and a badge office: when it is down, existing traffic keeps flowing, but nothing new can change.

## Learning objectives

After this module you can:

- Name the four jobs `istiod` does and describe how the mesh degrades when each one fails.
- Explain why running proxies keep serving traffic without a control plane, and what ends that grace period.
- Tell `istiod`'s readiness apart from its health, and say what a climbing restart count on a `Running` pod means.
- Read `istiod`'s metrics and explain `pilot_xds_pushes`, `pilot_xds_push_errors`, `pilot_total_xds_rejects` and `pilot_proxy_convergence_time`.
- Explain why a counter that has never gone up is missing rather than zero.
- Predict what happens to new pods during a control plane outage, for each webhook `failurePolicy`.
- Explain where a rejected configuration shows up, even though `kubectl apply` reported success.
- Recognise the slow version of the same failure: a control plane short of memory or processor time.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** You can use `kubectl`, including `logs`, `exec` and `scale`.
- **No Istio objects to write.** This module is about the component that serves Istio objects, not about writing them.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` ready to use. It has one planet (namespace), **`cphealth-demo`**, with injection switched on:

| Ship | What it does |
| --- | --- |
| `notification-service-v1` | The app, behind the beacon (Service) `notification-service` on port `80` |
| `tester` | Your test ship: a client pod with `curl`. Every test signal is sent from here |

Nothing is broken when the playground starts. In one part you take `istiod` down yourself, on purpose. That is safe here, because the training solar system is yours and you can throw it away. On a shared cluster, the same command would stop every team's deployments.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts, in order

1. [Four Jobs In One Process](./course-01-the-four-jobs-of-istiod.md)
2. [The Instruments](./course-02-instruments-logs-and-metrics.md)
3. [Take Mission Control Away](./course-03-take-mission-control-away.md)
4. [Accepted, Never Applied](./course-04-accepted-never-applied.md)
5. [Wrap-Up: Mission Debrief](./course-05-wrap-up.md)

## Why this matters

If mission control is not healthy, nothing else you check means much. A route that was never sent cannot be debugged in the proxy, and a policy that `istiod` refused will never take effect. Checking the control plane first takes two minutes, and it stops you from fixing YAML that was right all along.
