# Section 010: Troubleshooting Configuration With istioctl

The Kubernetes API server checks that every Istio object you apply has the right shape. It does not check that the object points at anything real. That gap is where many confusing mesh problems live. A `VirtualService` that routes to a subset no `DestinationRule` defines applies without an error, and every request to that host then fails.

This section gives you the commands that close the gap, and it comes first because every other kind of investigation is slower. `istioctl analyze` reads your configuration the way `istiod`, Istio's control plane, does and names every reference that does not resolve. `istioctl x describe pod` answers a different question: what does all of this configuration add up to for one workload? And `istioctl bug-report` collects the state of the control plane and selected proxies into an archive, for when someone else has to find the answer.

**Exam topic covered:** Troubleshooting Configuration

## What you will learn

- The difference between a valid object and a correct configuration, and why a clean `kubectl apply` proves very little.
- Running `istioctl analyze` against a namespace, the whole mesh, and a file that has not been applied yet.
- Reading an analyzer message as severity, `IST####` code and blamed object, and why messages below `Error` are often the real cause.
- `IST0101`, `IST0102` and `IST0103`: what each one means and what it costs you.
- Choosing between `istioctl validate` and `istioctl analyze`.
- Reading every section of `istioctl x describe pod`, including the warnings at the bottom.
- The effective mutual TLS (mTLS) mode, and why `describe` shows what a workload really ended up with.
- Raising one Envoy log scope to `debug` at runtime, reading the decision, and putting it back to `warning`.
- Producing a `bug-report` archive limited to chosen workloads and a time window.

## The learning path

Work through the modules in order. Each module has a landing page, a few short parts, a graded lab right after the part it tests, and a summary. Each module also has its own playground, a cluster where you can explore freely, and the landing page of each module starts it for you.

### 1. Find Configuration Errors With istioctl analyze

The module starts at its landing page, which also launches the playground. The playground holds the namespace `analyze-demo` with configuration that is broken in two ways the API server accepted without an error.

1. What The API Server Checks, And What It Cannot
2. Reading What The Analyzer Says
3. Choosing The Right Analysis Source, followed by the lab **Find And Fix The Configuration Errors**
4. Summary

### 2. Summarise A Workload With describe, Capture A Cluster With bug-report

The module starts at its landing page, which also launches the playground. The playground holds the namespace `describe-demo`, where four Istio objects apply to one workload. Nothing is broken; the skill is reading a working system.

1. What describe Resolves For One Workload
2. Making A Proxy Narrate One Decision, followed by the lab **Widen A Policy Without Weakening The Mesh**
3. Capturing A Cluster With bug-report, followed by the lab **Capture A Limited bug-report Archive**
4. Summary

## Section capstone: Repair A Namespace Nothing Validates

The capstone is one graded scenario that combines both modules. The namespace `audit-demo` was set up in a hurry before a compliance review. Every object applied without an error, and yet the namespace is not in the mesh, does not route to a real subset, and does not restrict anything. Several faults are not reported as `Error`s, and one is not reported by any analyzer at all. Work it after the module labs.

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
