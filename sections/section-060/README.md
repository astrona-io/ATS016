# Section 060: Troubleshooting With Mesh Observability

Every section before this one works on a single proxy or a single pair of workloads. That is the right altitude once you know where to look, and the wrong one when the report is "something is slow" and forty services are involved.

This section is the view from above, and the important thing about both tools in it is that neither is a new source of truth. Kiali draws `istioctl analyze`'s findings and Istio's metrics as a picture. Grafana draws the same metrics as graphs. Everything they show can be read from a proxy by hand — which is exactly why you can trust them, and why a red edge is a place to start rather than an answer.

**Curriculum items covered:** Troubleshooting Configuration, Troubleshooting the Mesh Data Plane

---

## What You Will Master

- Kiali's two data sources, and why it shows nothing without either.
- What a red edge states precisely, and what it does not.
- Finding `istioctl analyze`'s output inside Kiali's Istio Config view.
- Why a running, healthy service can be absent from the graph entirely.
- The security badge, and the `connection_security_policy` label behind it.
- Istio's standard metrics: `istio_requests_total`, the duration histogram, the byte histograms, the TCP counters.
- The `reporter` label — client view against server view — and what a disagreement between them proves.
- PromQL for a request rate, an error ratio and a latency percentile, including why `le` must survive the aggregation.
- Querying Prometheus over its HTTP API when no browser is available.
- Which of Istio's four Grafana dashboards answers which question.

---

## The Learning Path

### 1. Troubleshoot With Kiali
*   **Module Reader:** **[Module 1: Troubleshoot With Kiali](./module-01/course.md)**
    *   Deep dive, in order:
        1. [What Kiali Is Built From](./module-01/course-01-what-kiali-is-built-from.md)
        2. [Reading The Graph](./module-01/course-02-reading-the-graph.md)
        3. [Validations, Badges And Cross-Checking](./module-01/course-03-validations-and-cross-checking.md)
*   **Hands-on Playground:** `sections/section-060/module-01/playground` — a kind cluster with Istio, the Prometheus and Kiali addons, and namespace `kiali-demo`. No traffic flows at startup, so the graph begins empty — which is the first thing the module has you fix.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-060/module-01/playground
    ```
*   **Graded Lab:** **[An Empty Graph And A Red Badge](./module-01/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-060/module-01/labs/lab-01
    ```

### 2. Troubleshoot With Prometheus And Grafana
*   **Module Reader:** **[Module 2: Troubleshoot With Prometheus And Grafana](./module-02/course.md)**
    *   Deep dive, in order:
        1. [The Metrics Pipeline](./module-02/course-01-the-metrics-pipeline.md)
        2. [The reporter Label And PromQL Patterns](./module-02/course-02-reporter-and-promql.md)
        3. [Measuring A Known Failure, And Grafana](./module-02/course-03-measuring-a-failure-and-grafana.md)
*   **Hands-on Playground:** `sections/section-060/module-02/playground` — a kind cluster with Istio, the Prometheus and Grafana addons, and namespace `metrics-demo`, plus a fault manifest that injects a known error rate and a known delay to check your queries against.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-060/module-02/playground
    ```
*   **Graded Lab:** **[Measure The Failure Before You Fix It](./module-02/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-060/module-02/labs/lab-01
    ```

Both playgrounds install observability addons at startup, so they take longer to come up than the others. Each is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished — the name is printed in each module's playground callout.

---

## Section Capstone

**[Measure A Failure, Fix It, Prove It](./capstone/labs/lab-01/question.md)** — one graded scenario
combining this section's modules, with several independent faults to find and
fix. Work it after the module labs.

> A team reports that `notification-service` in `obscapstone-demo` "fails sometimes". Somebody opened Kiali, saw an empty graph, and escalated it as a total outage. Prometheus, Kiali and Grafana are all installed.

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-060/capstone/labs/lab-01
astrona submit
```
