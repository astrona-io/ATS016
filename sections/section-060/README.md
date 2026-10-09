# Section 060: Troubleshooting With Mesh Observability

Astronaut, until now you looked at one ship, or one pair of ships, at a time. That is the right view once you know where to look. It is the wrong view when the report says "something is slow" and forty services are involved.

This section is the view from mission control. It covers three tools: Kiali, the tactical map that shows every ship and signal path on one screen; Prometheus, the telemetry recorder that counts every signal; and Grafana, the dashboard screens. None of them is a new source of truth. Kiali draws the findings of `istioctl analyze` and Istio's metrics as a picture. Grafana draws the same metrics as graphs. You can read everything they show from a proxy by hand, which is exactly why you can trust them, and why a red edge is a place to start, not an answer.

**Curriculum items covered:** Troubleshooting Configuration, Troubleshooting the Mesh Data Plane

## What you will learn

- Kiali's two data sources, and why it shows nothing without either one.
- What a red edge says exactly, and what it does not say.
- Finding the findings of `istioctl analyze` inside Kiali's Istio Config view.
- Why a running, healthy service can be missing from the graph.
- The security padlock, and the `connection_security_policy` label behind it.
- Istio's standard metrics: `istio_requests_total`, the duration histogram, the byte histograms and the TCP counters.
- The `reporter` label, which says which ship filed the report: the client's view or the server's view, and what a difference between them proves.
- PromQL (the Prometheus query language) for a request rate, an error ratio and a latency percentile, including why `le` must survive the aggregation.
- Querying Prometheus over its HTTP interface when no browser is available.
- Which of Istio's four Grafana dashboards answers which question.

## The modules

Each module has a landing page, a few short parts, a hands-on playground and a graded mission right after the part that teaches its skill. Both playgrounds install the observability add-ons at startup, so they take longer to come up than other playgrounds.

### 1. Troubleshoot With Kiali

Start at the landing page, **[Troubleshoot With Kiali](./module-01/course.md)**, then read the parts in order:

1. [What Kiali Is Built From](./module-01/course-01-what-kiali-is-built-from.md)
2. [Reading The Graph](./module-01/course-02-reading-the-graph.md)
3. [Validations, Badges And Cross-Checking](./module-01/course-03-validations-and-cross-checking.md), followed by the mission **[An Empty Graph And A Red Badge](./module-01/labs/lab-01/question.md)**
4. [Wrap-Up: Mission Debrief](./module-01/course-04-wrap-up.md)

The playground is a `kind` cluster with Istio, the Prometheus and Kiali add-ons, and the namespace `kiali-demo`. No traffic flows at startup, so the graph begins empty, and that is the first thing the module has you fix.

### 2. Troubleshoot With Prometheus And Grafana

Start at the landing page, **[Troubleshoot With Prometheus And Grafana](./module-02/course.md)**, then read the parts in order:

1. [The Metrics Pipeline](./module-02/course-01-the-metrics-pipeline.md)
2. [The reporter Label And PromQL Patterns](./module-02/course-02-reporter-and-promql.md)
3. [Measuring A Known Failure](./module-02/course-03-measuring-a-known-failure.md)
4. [Grafana, Flight Logs And Proving The Fix](./module-02/course-04-grafana-and-proving-the-fix.md), followed by the mission **[Measure The Failure Before You Fix It](./module-02/labs/lab-01/question.md)**
5. [Wrap-Up: Mission Debrief](./module-02/course-05-wrap-up.md)

The playground is a `kind` cluster with Istio, the Prometheus and Grafana add-ons, and the namespace `metrics-demo`. The parts give you a fault drill with a known error rate and a known delay to check your queries against.

## Section capstone

**[Measure A Failure, Fix It, Prove It](./capstone/labs/lab-01/question.md)** is one graded scenario that combines both modules, with several separate faults to find and fix. Work it after the module missions.

A team reports that `notification-service` in `obscapstone-demo` "fails sometimes". Somebody opened Kiali, saw an empty graph, and escalated it as a total outage. Prometheus, Kiali and Grafana are all installed, and nobody has measured anything.

Start the capstone:

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-060/capstone/labs/lab-01
```

When you think you are done, send it for grading:

```bash
astrona submit -c sections/section-060/capstone/labs/lab-01
```

When you are finished, remove it. The command takes the capstone's name, not its folder path:

```bash
astrona destroy ats-016-capstone-060
```
