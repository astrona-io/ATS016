# Section 030: Troubleshooting The Mesh Control Plane

A broken control plane does not look like an outage. Requests keep succeeding, because every sidecar proxy works with the configuration it already holds and the certificate it already has. What stops is *change*, and nothing reports that change has stopped. `istiod` is Istio's control plane: it sends configuration and certificates to every sidecar proxy, and it serves the webhooks that add sidecars to pods and check Istio objects.

This section follows the path configuration takes to reach a proxy, and each module answers one question about it. Is `istiod` healthy enough to serve anything? Did what it sent actually arrive at each proxy? And the question that makes the other two irrelevant when the answer is no: does the pod have a sidecar proxy at all?

**Exam topic covered:** Troubleshooting the Mesh Control Plane

## What you will learn

- The four jobs `istiod` does (xDS server, certificate authority, injection webhook, validation webhook) and how the mesh degrades when each one fails.
- What keeps working during a control plane outage, for how long, and what stops at once.
- How to read `istiod`'s readiness, restart count, log and its `pilot_*` metrics on port `15014`.
- Where a rejected configuration shows up, even though `kubectl apply` reported success.
- The xDS protocol and its four main resource types: `CDS`, `LDS`, `EDS` and `RDS`.
- What `SYNCED`, `STALE`, `NOT SENT` and `ERROR` in `istioctl proxy-status -v 1` rule in and out, and what `SYNCED` does *not* prove.
- Why a workload missing from `istioctl proxy-status` has no state at all, and the three causes in order.
- How to spot version skew and confirm which `istiod` revision serves a workload.
- The six-step sidecar injection checklist: namespace label, pod template label, pod age, webhook health, revision, pod spec.
- Why labelling a namespace never changes pods that already exist.

## The learning path

Each module has a landing page, a few short parts, a graded lab right after the part it tests, and a summary. Each module also has an ungraded playground: launch it from the module's landing page and keep it running while you read.

The first module, **Check Control Plane Health**, splits `istiod` into its four jobs, reads its pod status, log and metrics, scales it to zero on purpose, and finds an invalid object that was stored without validation. Its parts are Four Jobs In One Process, The Instruments, Take The Control Plane Away, and Stored Without Validation, followed by the lab **The Mesh Works And Nothing Can Change**.

The second module, **Diagnose Configuration Sync With proxy-status**, explains how configuration travels from `istiod` to each proxy and is acknowledged, reads the `istioctl proxy-status` table, and diagnoses a workload that is missing from it. Its parts are How Configuration Reaches A Proxy, Reading The Table, and Absence, And The Per-Proxy Diff, followed by the lab **One Workload Vanished From The Mesh**.

The third module, **Debug A Workload With No Sidecar**, explains how the injection webhook adds a sidecar to a pod, which labels win, and how to work the checklist when a pod started without one. Its parts are How Injection Actually Happens, Labels, Selectors And Precedence, Working The Checklist, and Fix It And Prove It Joined, followed by the lab **Bring An Exempt Workload Back Into The Mesh**.

When you finish a module, its summary page removes the playground for you.

## Section capstone

**Three Workloads, Three Different Control Plane Faults** is one graded scenario that combines all three modules. Three workloads in two namespaces are out of step with the control plane, each for a different reason: a pod-template opt-out, a namespace pinned to a revision that does not exist, and an invalid `VirtualService` that was stored without validation and redirects every request. Work it after the module labs.

Start it:

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/capstone/labs/lab-01
```

Send it for grading when you are done:

```bash
astrona submit -c sections/section-030/capstone/labs/lab-01
```

Remove it afterwards:

```bash
astrona destroy ats-016-capstone-030
```
