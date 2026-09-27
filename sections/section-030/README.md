# Section 030: Troubleshooting The Mesh Control Plane

A broken control plane does not look like an outage. Traffic keeps flowing, because every proxy serves from the configuration it already holds and the certificate it already has. What stops is *change* — and nothing reports that change has stopped.

This section works down the path configuration takes to reach a workload, and each module answers one question about it. Is `istiod` healthy enough to serve anything? Did what it sent actually arrive? And, the question that invalidates the other two when the answer is no: is there a proxy on that workload at all?

**Curriculum item covered:** Troubleshooting the Mesh Control Plane

---

## What You Will Master

- The four jobs `istiod` performs — xDS server, certificate authority, injection webhook, validation webhook — and how the mesh degrades when each fails.
- What survives a control plane outage, for how long, and what stops immediately.
- `istiod`'s readiness, restart count, logs and the `pilot_*` metrics on port 15014.
- Where a rejected configuration becomes visible, given that `kubectl apply` reported success.
- xDS and its four resource types: `CDS`, `LDS`, `EDS`, `RDS`.
- `SYNCED`, `STALE` and `NOT SENT` — what each rules in and out, and what `SYNCED` does *not* prove.
- Why a workload missing from `istioctl proxy-status` has no state at all, and the three causes in order of likelihood.
- Spotting control plane version skew and confirming which revision serves a workload.
- The six-step sidecar injection checklist: namespace label, pod template label, pod age, webhook health, revision, pod spec.
- Why labelling a namespace never affects pods that already exist.

---

## The Learning Path

### 1. Check Control Plane Health
*   **Module Reader:** **[Module 1: Check Control Plane Health](./module-01/course.md)**
    *   Deep dive, in order:
        1. [Four Jobs In One Process](./module-01/course-01-the-four-jobs-of-istiod.md)
        2. [The Instruments](./module-01/course-02-instruments-logs-and-metrics.md)
        3. [Outage Anatomy And Rejected Configuration](./module-01/course-03-outage-anatomy-and-rejects.md)
*   **Hands-on Playground:** `sections/section-030/module-01/playground` — a kind cluster with Istio installed and namespace `cphealth-demo`. Nothing is broken; you take `istiod` down yourself and watch which half of the mesh notices.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-01/playground
    ```
*   **Graded Lab:** **[The Mesh Works And Nothing Can Change](./module-01/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-01/labs/lab-01
    ```

### 2. Diagnose Config Sync With proxy-status
*   **Module Reader:** **[Module 2: Diagnose Config Sync With proxy-status](./module-02/course.md)**
    *   Deep dive, in order:
        1. [How Configuration Reaches A Proxy](./module-02/course-01-xds-and-acknowledgement.md)
        2. [Reading The Table](./module-02/course-02-reading-the-proxy-status-table.md)
        3. [Absence, And The Per-Proxy Diff](./module-02/course-03-absence-and-per-proxy-diff.md)
*   **Hands-on Playground:** `sections/section-030/module-02/playground` — a kind cluster with Istio installed and namespace `proxysync-demo`, where every proxy starts fully `SYNCED`.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-02/playground
    ```
*   **Graded Lab:** **[One Workload Vanished From The Mesh](./module-02/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-02/labs/lab-01
    ```

### 3. Debug A Workload With No Sidecar
*   **Module Reader:** **[Module 3: Debug A Workload With No Sidecar](./module-03/course.md)**
    *   Deep dive, in order:
        1. [How Injection Actually Happens](./module-03/course-01-the-injection-webhook.md)
        2. [Labels, Selectors And Precedence](./module-03/course-02-labels-and-precedence.md)
        3. [Working The Checklist](./module-03/course-03-working-the-checklist.md)
*   **Hands-on Playground:** `sections/section-030/module-03/playground` — a kind cluster with Istio installed and namespace `noinject-demo`, containing one normally injected workload and one that is quietly outside the mesh.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-03/playground
    ```
*   **Graded Lab:** **[Bring An Exempt Workload Back Into The Mesh](./module-03/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-03/labs/lab-01
    ```

Each playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished — the name is printed in each module's playground callout.

---

## Section Capstone

**[Three Workloads, Three Different Control Plane Faults](./capstone/labs/lab-01/question.md)** — one graded scenario
combining this section's modules, with several independent faults to find and
fix. Work it after the module labs.

> A platform migration left three workloads in an inconsistent state across two namespaces:

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/capstone/labs/lab-01
astrona submit
```
