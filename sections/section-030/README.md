# Section 030: Troubleshooting The Mesh Control Plane

Astronaut, a broken mission control does not look like an outage. Signals keep flowing, because every communications officer (sidecar proxy) works from the orders it already holds and the ID badge (certificate) it already carries. What stops is *change*, and nothing reports that change has stopped.

This section follows the path configuration takes to reach a ship, and each module answers one question about it. Is `istiod`, mission control, healthy enough to serve anything? Did what it sent actually arrive? And the question that cancels the other two when the answer is no: is there a communications officer on that ship at all?

**Exam topic covered:** Troubleshooting the Mesh Control Plane

## What you will learn

- The four jobs `istiod` does (xDS server, certificate authority, injection webhook, validation webhook) and how the mesh degrades when each one fails.
- What keeps working during a control plane outage, for how long, and what stops at once.
- How to read `istiod`'s readiness, restart count, logs and its `pilot_*` metrics on port `15014`.
- Where a rejected configuration shows up, even though `kubectl apply` reported success.
- The xDS protocol and its four main resource types: `CDS`, `LDS`, `EDS` and `RDS`.
- What `SYNCED`, `STALE` and `NOT SENT` rule in and out, and what `SYNCED` does *not* prove.
- Why a workload missing from `istioctl proxy-status` has no state at all, and the three causes in order.
- How to spot version skew and confirm which `istiod` revision serves a workload.
- The six-step sidecar injection checklist: namespace label, pod template label, pod age, webhook health, revision, pod spec.
- Why labelling a namespace never changes pods that already exist.

## The learning path

Each module has a landing page, a few short parts, a graded mission right after the part it tests, and a wrap-up. Each module also has an ungraded playground: launch it from the module's landing page and keep it running while you read.

### 1. Check Control Plane Health

Take mission control apart into its four jobs, read its instruments, switch it off on purpose, and find configuration it stored but never sent.

- [Check Control Plane Health](./module-01/course.md) (landing page)
  1. [Four Jobs In One Process](./module-01/course-01-the-four-jobs-of-istiod.md)
  2. [The Instruments](./module-01/course-02-instruments-logs-and-metrics.md)
  3. [Take Mission Control Away](./module-01/course-03-take-mission-control-away.md)
  4. [Accepted, Never Applied](./module-01/course-04-accepted-never-applied.md), then the mission **[The Mesh Works And Nothing Can Change](./module-01/labs/lab-01/question.md)**
  5. [Wrap-Up: Mission Debrief](./module-01/course-05-wrap-up.md)

### 2. Diagnose Configuration Sync With proxy-status

Learn how orders travel from `istiod` to each proxy and are confirmed, read mission control's roll call, and diagnose a ship that is missing from it.

- [Diagnose Configuration Sync With proxy-status](./module-02/course.md) (landing page)
  1. [How Configuration Reaches A Proxy](./module-02/course-01-xds-and-acknowledgement.md)
  2. [Reading The Table](./module-02/course-02-reading-the-proxy-status-table.md)
  3. [Absence, And The Per-Proxy Diff](./module-02/course-03-absence-and-per-proxy-diff.md), then the mission **[One Workload Vanished From The Mesh](./module-02/labs/lab-01/question.md)**
  4. [Wrap-Up: Mission Debrief](./module-02/course-04-wrap-up.md)

### 3. Debug A Workload With No Sidecar

Learn how the launch-pad crew (the injection webhook) puts a communications officer on board, which labels win, and how to work the checklist when a ship launched without one.

- [Debug A Workload With No Sidecar](./module-03/course.md) (landing page)
  1. [How Injection Actually Happens](./module-03/course-01-the-injection-webhook.md)
  2. [Labels, Selectors And Precedence](./module-03/course-02-labels-and-precedence.md)
  3. [Working The Checklist](./module-03/course-03-working-the-checklist.md)
  4. [Fix It And Prove It Joined](./module-03/course-04-fix-and-prove.md), then the mission **[Bring An Exempt Workload Back Into The Mesh](./module-03/labs/lab-01/question.md)**
  5. [Wrap-Up: Mission Debrief](./module-03/course-05-wrap-up.md)

When you finish a module, clean up its playground with `astrona destroy <playground name>`. Each wrap-up page gives the exact name.

## Section capstone

**[Three Workloads, Three Different Control Plane Faults](./capstone/labs/lab-01/question.md)** is one graded scenario that combines all three modules. Three workloads on two planets are out of step with mission control, each for a different reason: a ship's own opt-out, a planet tied to a revision that does not exist, and a flight plan that was stored but never sent. Work it after the module missions.

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
