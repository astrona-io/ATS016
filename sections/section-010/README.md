# Section 010: Troubleshooting Configuration With istioctl

The Kubernetes API server checks that an Istio resource is the right *shape*. It does not check that the resource refers to anything real. That gap is where most confusing mesh problems live: a `VirtualService` routing to a subset nobody defined applies cleanly, reports no error, and breaks every request to that host.

This section is the two commands that close the gap, and it comes first because everything else in the course is slower. Module 1 is `istioctl analyze`, which reads your configuration the way `istiod` does and names what does not resolve. Module 2 is `istioctl x describe pod`, which answers the other question — not "is this coherent" but "what does all of it add up to for *this* workload" — plus `bug-report` for when the answer has to be found somewhere else.

**Curriculum item covered:** Troubleshooting Configuration

---

## What You Will Master

- The difference between schema validity and semantic correctness, and why a clean `kubectl apply` proves almost nothing.
- Running `istioctl analyze` against a namespace, the whole mesh, and a file that has not been applied yet.
- Reading an analyzer message as severity + `IST####` code + blamed object, and why the Warnings are usually the real cause.
- `IST0101`, `IST0102` and `IST0103` — what each means and what it costs you.
- Choosing between `istioctl validate` and `istioctl analyze`.
- Reading every section of `istioctl x describe pod`, including the warnings at the bottom that most people scroll past.
- Effective mTLS mode, and why only `describe` can tell you what a workload actually ended up with.
- Raising one Envoy log scope to `debug` at runtime, reading the decision, and putting it back.
- Producing a `bug-report` archive scoped by namespace and time window.

---

## The Learning Path

### 1. Find Configuration Errors With istioctl analyze
*   **Module Reader:** **[Module 1: Find Configuration Errors With istioctl analyze](./module-01/course.md)**
    *   Deep dive, in order:
        1. [What The API Server Checks, And What It Cannot](./module-01/course-01-admission-and-the-analysis-gap.md)
        2. [Reading What The Analyzer Says](./module-01/course-02-reading-analyzer-messages.md)
        3. [Choosing The Right Analysis Source](./module-01/course-03-analysis-sources-and-the-fix-loop.md)
*   **Hands-on Playground:** `sections/section-010/module-01/playground` — a kind cluster with Istio installed, namespace `analyze-demo`, and Istio configuration that is deliberately broken in two ways the API server accepted without complaint.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-01/playground
    ```
*   **Graded Lab:** **[Find And Fix The Configuration Errors In `analyze-demo`](./module-01/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-01/labs/lab-01
    ```

### 2. Summarise A Workload With describe, Capture A Cluster With bug-report
*   **Module Reader:** **[Module 2: Summarise A Workload With describe, Capture A Cluster With bug-report](./module-02/course.md)**
    *   Deep dive, in order:
        1. [What describe Resolves For One Workload](./module-02/course-01-what-describe-resolves.md)
        2. [Making A Proxy Narrate One Decision](./module-02/course-02-envoy-log-scopes-at-runtime.md)
        3. [Capturing A Cluster With bug-report](./module-02/course-03-bug-report-and-handover.md)
*   **Hands-on Playground:** `sections/section-010/module-02/playground` — a kind cluster with Istio installed and namespace `describe-demo`, where four Istio objects all apply to one workload. Nothing is broken; the exercise is reading a working system.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-02/playground
    ```
*   **Graded Lab:** **[Widen A Policy Without Weakening The Mesh](./module-02/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-02/labs/lab-01
    ```

Each playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished — the name is printed in each module's playground callout.

---

## Section Capstone

**[Repair A Namespace Nothing Validates](./capstone/labs/lab-01/question.md)** — one graded scenario
combining this section's modules, with several independent faults to find and
fix. Work it after the module labs.

> `audit-demo` was set up in a hurry before a compliance review. Everything in it applied without a single error, and the team believes the namespace is:

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/capstone/labs/lab-01
astrona submit
```
