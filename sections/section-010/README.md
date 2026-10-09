# Section 010: Troubleshooting Configuration With istioctl

Astronaut, the Kubernetes API server is the registry office: it checks that every Istio object you file has the right *shape*. It does not check that the object points at anything real. That gap is where most confusing mesh problems live. A `VirtualService` (the flight plan for signals) that routes to a subset nobody defined applies cleanly, reports no error, and breaks every request to that host.

This section gives you the commands that close the gap. It comes first because every other kind of investigation is slower. `istioctl analyze` is the pre-flight inspector: it reads your configuration the way `istiod` (mission control) does and names what does not resolve. `istioctl x describe pod` is the ship's dossier: it answers a different question, "what does all of this add up to for *this* workload?" And `istioctl bug-report` is the black box, for when someone else has to find the answer.

**Exam topic covered:** Troubleshooting Configuration

## What you will master

- The difference between a valid shape and a correct meaning, and why a clean `kubectl apply` proves very little.
- Running `istioctl analyze` against a namespace, the whole mesh, and a file that has not been applied yet.
- Reading an analyzer message as severity, `IST####` code and blamed object, and why the Warnings are often the real cause.
- `IST0101`, `IST0102` and `IST0103`: what each means and what it costs you.
- Choosing between `istioctl validate` and `istioctl analyze`.
- Reading every section of `istioctl x describe pod`, including the warnings at the bottom that most people scroll past.
- The effective mutual TLS mode, and why only `describe` can tell you what a workload really ended up with.
- Raising one Envoy log scope to `debug` at runtime, reading the decision, and putting it back.
- Producing a `bug-report` archive limited to a namespace and a time window.

## The learning path

Work through the modules in order. Each module has a landing page, a few short parts, a graded mission right after the part it tests, and a wrap-up. Each module also has its own playground: a training solar system where you can explore freely. The landing page of each module starts it for you.

### 1. Find Configuration Errors With istioctl analyze

The module starts at its landing page, which also launches the playground. The playground holds the namespace `analyze-demo` with configuration that is broken in two ways the API server accepted without an error.

1. What The API Server Checks, And What It Cannot
2. Reading What The Analyzer Says
3. Choosing The Right Analysis Source, followed by the lab **Find And Fix The Configuration Errors**
4. Summary

### 2. Summarise A Workload With describe, Capture A Cluster With bug-report

Start at the **[module landing page](./module-02/course.md)**. The playground holds the namespace `describe-demo`, where four Istio objects all apply to one workload. Nothing is broken; the skill is reading a working system.

1. [What describe Resolves For One Workload](./module-02/course-01-what-describe-resolves.md)
2. [Making A Proxy Narrate One Decision](./module-02/course-02-envoy-log-scopes-at-runtime.md), followed by the mission **[Widen A Policy Without Weakening The Mesh](./module-02/labs/lab-01/question.md)**
3. [Capturing A Cluster With bug-report](./module-02/course-03-bug-report-and-handover.md)
4. [Wrap-Up: Mission Debrief](./module-02/course-04-wrap-up.md)

## Section capstone: Repair A Namespace Nothing Validates

**[Repair A Namespace Nothing Validates](./capstone/labs/lab-01/question.md)** is one graded scenario that combines both modules. The planet `audit-demo` was set up in a hurry before a compliance review. Every object applied without a single error, and yet the namespace is not in the mesh, does not route to a real subset, and does not restrict anything. Several faults are not Errors, and one is not reported by any analyzer at all. Work it after the module missions.

Start the capstone:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/capstone/labs/lab-01
```

When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-010/capstone/labs/lab-01
```

When the capstone is done, remove it:

```sh
astrona destroy ats-016-capstone-010
```
