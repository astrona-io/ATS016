# ATS016 — Troubleshooting (Istio Certified Associate)

Course material for the **Troubleshooting** domain of the Istio Certified
Associate (ICA) exam, which is **20% of the exam**. Built for **Istio 1.30.5**.

Everything lives under `sections/`. Each section contains:

- **Modules** — a reading chapter split into a short landing page, ordered
  deep-dive parts and a wrap-up page, a throwaway **playground** to explore in,
  and a graded **lab** with an exam-style task, placed right after the part it
  tests.
- **A capstone** — one larger graded lab combining that section's modules into a
  single scenario with several independent faults.

Read a module, run its playground alongside it, work the module's lab without
looking at the solution, then finish the section with its capstone.

---

## Sections

| Section | Title | Modules | Labs | Curriculum item |
| --- | --- | --- | --- | --- |
| [010](sections/section-010) | Troubleshooting Configuration With istioctl | 2 | 2 + capstone | Troubleshooting Configuration |
| [020](sections/section-020) | Debugging Conflicting And Shadowed Routes | 1 | 1 + capstone | Troubleshooting Configuration |
| [030](sections/section-030) | Troubleshooting The Mesh Control Plane | 3 | 3 + capstone | Troubleshooting the Mesh Control Plane |
| [040](sections/section-040) | Reading Data Plane Configuration | 2 | 2 + capstone | Troubleshooting the Mesh Data Plane |
| [050](sections/section-050) | Debugging Data Plane Request Failures | 2 | 2 + capstone | Troubleshooting the Mesh Data Plane |
| [060](sections/section-060) | Troubleshooting With Mesh Observability | 2 | 2 + capstone | Troubleshooting Configuration / the Mesh Data Plane |

The order is the order of an investigation, outside in. `istioctl analyze` comes
first because it is the cheapest question to ask. Control plane health comes
before data plane configuration, because there is no point debugging a route
that was never pushed — or a policy on a pod with no sidecar to enforce it.
Observability comes last, because Kiali and Grafana render data the earlier
sections teach you to read by hand.

---

## Modules

| Module | Reader | Parts | Lab |
| --- | --- | --- | --- |
| 010-01 | [Find Configuration Errors With istioctl analyze](sections/section-010/module-01/course.md) | 3 | [lab-01](sections/section-010/module-01/labs/lab-01) |
| 010-02 | [Summarise A Workload With describe, Capture A Cluster With bug-report](sections/section-010/module-02/course.md) | 3 | [lab-01](sections/section-010/module-02/labs/lab-01) |
| 020-01 | [Debug Conflicting And Shadowed Routes](sections/section-020/module-01/course.md) | 3 | [lab-01](sections/section-020/module-01/labs/lab-01) |
| 030-01 | [Check Control Plane Health](sections/section-030/module-01/course.md) | 4 | [lab-01](sections/section-030/module-01/labs/lab-01) |
| 030-02 | [Diagnose Configuration Sync With proxy-status](sections/section-030/module-02/course.md) | 3 | [lab-01](sections/section-030/module-02/labs/lab-01) |
| 030-03 | [Debug A Workload With No Sidecar](sections/section-030/module-03/course.md) | 4 | [lab-01](sections/section-030/module-03/labs/lab-01) |
| 040-01 | [Read The Proxy Configuration](sections/section-040/module-01/course.md) | 5 | [lab-01](sections/section-040/module-01/labs/lab-01) |
| 040-02 | [Debug A 503 Caused By A Missing Subset](sections/section-040/module-02/course.md) | 4 | [lab-01](sections/section-040/module-02/labs/lab-01) |
| 050-01 | [Read Envoy Access Logs And Response Flags](sections/section-050/module-01/course.md) | 5 | [lab-01](sections/section-050/module-01/labs/lab-01) |
| 050-02 | [Debug A 503 Caused By An mTLS Mismatch](sections/section-050/module-02/course.md) | 3 | [lab-01](sections/section-050/module-02/labs/lab-01) |
| 060-01 | [Troubleshoot With Kiali](sections/section-060/module-01/course.md) | 3 | [lab-01](sections/section-060/module-01/labs/lab-01) |
| 060-02 | [Troubleshoot With Prometheus And Grafana](sections/section-060/module-02/course.md) | 4 | [lab-01](sections/section-060/module-02/labs/lab-01) |

---

## Capstones

One per section, each combining that section's modules into a single scenario
with several independent faults.

| Capstone | Scenario | Faults |
| --- | --- | --- |
| [010](sections/section-010/capstone/labs/lab-01) | Repair A Namespace Nothing Validates | uninjected namespace, two dangling references, a policy whose selector matches nothing |
| [020](sections/section-020/capstone/labs/lab-01) | Consolidate Three Claimants Into One Route Table | three objects claiming one host, plus a shadowed rule |
| [030](sections/section-030/capstone/labs/lab-01) | Three Workloads, Three Different Control Plane Faults | pod-template opt-out, a missing revision, config accepted and never pushed |
| [040](sections/section-040/capstone/labs/lab-01) | Two 503s, Two Different Stages | a missing cluster, and a port that declares no protocol |
| [050](sections/section-050/capstone/labs/lab-01) | Diagnose Two Failures From The Logs Alone | an mTLS mismatch hiding an authorization denial |
| [060](sections/section-060/capstone/labs/lab-01) | Measure A Failure, Fix It, Prove It | fault injection, a dangling subset, and a duplicated host |

---

## The method this course teaches

Every module is one step of the same sequence, worked outside in. Asked in this
order, each question either produces the answer or eliminates a whole class of
causes:

1. **Is the configuration coherent?** — `istioctl analyze` (010)
2. **What does it add up to for this workload?** — `istioctl x describe pod` (010)
3. **Is the control plane healthy enough to serve anything?** — `istiod` logs and metrics (030)
4. **Did the configuration reach the proxy?** — `istioctl proxy-status` (030)
5. **Is there a proxy at all?** — sidecar injection (030)
6. **What is the proxy doing with it?** — `istioctl proxy-config` (020, 040)
7. **What did it actually do to this request?** — the access log and its response flag (050)
8. **How much, how bad, since when?** — Prometheus, Grafana and Kiali (060)

In a live incident the practical entry points are the access log (step 7) and
the Kiali graph (step 8), because both narrow the search in one command. The
rest of the sequence then applies to the pair of workloads they point at.

---

## Running a playground

Every module has one: a **kind** cluster with Istio 1.30.5 (`demo` profile)
installed and the module's starting workloads applied. Unlike a lab, it is
ungraded — it spins up, prepares the environment, and waits.

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/<section>/<module>/playground
astrona destroy <name>
```

The environment name is the playground's `metadata.name` in its `config.yaml`,
for example `ats-016-playground-010-01`; each module's landing page launches its
playground. Several playgrounds start with something deliberately broken — that
is the material, not a defect.

## Running a lab

Labs and capstones are graded. Read `question.md`, do the work, and submit:

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/<section>/<module>/labs/lab-01
astrona submit -c sections/<section>/<module>/labs/lab-01
astrona destroy <name>
```

`solution.md` is a full walkthrough with a submit loop — read it after you have
tried the task, not before. Each lab grades the **final cluster state** against
three or four independent checks, and several of them deliberately reject the
plausible-but-wrong fix (inventing a missing subset, relaxing mTLS to silence an
error, deleting a policy instead of correcting it).

The two observability sections install the Prometheus, Kiali and Grafana addons
at startup, so their environments take noticeably longer to come up.
