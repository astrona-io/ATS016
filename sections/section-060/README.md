# Section 060: Troubleshooting With Mesh Observability

Looking at one pod, or one pair of pods, is the right view once you know where to look. It is the wrong view when the report says "something is slow" and forty services are involved. This section covers the tools that show the whole mesh at once, and how far you can trust what they show.

It covers three tools. Kiali is the Istio console: it draws the services in the mesh as a graph and checks their Istio configuration. Prometheus is a monitoring system that collects the metrics every sidecar proxy records and answers queries over them. Grafana is a dashboard tool that draws those metrics as graphs. None of them is a new source of truth. Kiali draws the messages of `istioctl analyze` and Istio's metrics as a picture, and Grafana draws the same metrics as panels. You can read everything they show from a proxy by hand, which is why you can trust them, and why a red edge is a place to start, not an answer.

**Curriculum items covered:** Troubleshooting Configuration, Troubleshooting the Mesh Data Plane

## What you will learn

- Kiali's two data sources, and why it shows nothing without either one.
- What a red edge in the Kiali graph says exactly, and what it does not say.
- Finding the messages of `istioctl analyze` inside Kiali's Istio Config view.
- Why a running, healthy service can be missing from the graph.
- The security padlock, and the `connection_security_policy` label behind it.
- Istio's standard metrics: `istio_requests_total`, the duration histogram, the byte histograms and the TCP counters.
- The `reporter` label, which says whether the client proxy or the server proxy counted a request, and what a difference between the two proves.
- PromQL, the Prometheus query language, for a request rate, an error ratio and a latency percentile, including why `le` must survive the aggregation.
- Finding which caller a failure affects with `by (source_workload)`.
- Querying Prometheus over its HTTP interface when no browser is available.
- Which of Istio's Grafana dashboards answers which question.

## The modules

Each module has a landing page, a few short parts, a playground, a graded lab right after the part that teaches its skill, and a summary. Both playgrounds install the observability add-ons at startup, so they take longer to start than other playgrounds.

### 1. Troubleshoot With Kiali

The module starts at its landing page, which also launches the playground. The parts, in order:

1. What Kiali Is Built From
2. Reading The Graph
3. Validations, Badges And Cross-Checking, followed by the lab **An Empty Graph And A Red Badge**
4. Summary

The playground is a `kind` cluster with Istio, the Prometheus and Kiali add-ons, and the namespace `kiali-demo`. No traffic flows at startup, so the graph begins empty, and that is the first thing the module has you fix.

### 2. Troubleshoot With Prometheus And Grafana

The module starts at its landing page, which also launches the playground. The parts, in order:

1. The Metrics Pipeline
2. The reporter Label And PromQL Patterns
3. Measuring A Known Failure, followed by the lab **Find Which Caller Is Failing With PromQL**
4. Grafana, Access Logs And Proving The Fix, followed by the lab **Measure The Failure Before You Fix It**
5. Summary

The playground is a `kind` cluster with Istio, the Prometheus and Grafana add-ons, and the namespace `metrics-demo`. The parts inject a fault with a known error rate and a known delay, so you can check each query against the answer you expect.

## Section capstone

The capstone, **Measure A Failure, Fix It, Prove It**, is one graded scenario that combines both modules, with several separate faults to find and fix. Work it after the module labs.

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
