# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about Kiali, the tactical map in mission control. You learned what it draws, what it reads, and how to check every picture it shows.

**From [What Kiali Is Built From](./course-01-what-kiali-is-built-from.md):**

- Kiali stores nothing. It reads Istio objects from the Kubernetes API server and metrics from Prometheus, live, every time.
- No Prometheus, no graph. No traffic in the window, no graph either.
- An edge is a `sum(rate(istio_requests_total...))` grouped by source and destination: the response code becomes the colour, `connection_security_policy` becomes the padlock.
- To explain an empty graph, walk the path in order: traffic, the proxy's own metrics (`pilot-agent request GET stats/prometheus`), Prometheus, then Kiali's connection to Prometheus.

**From [Reading The Graph](./course-02-reading-the-graph.md):**

- The graph type (workload, service, versioned app, app) decides what a node is. The wrong one can hide a canary problem.
- An edge is a rate over a time window, and it fades after traffic stops.
- A red edge says that requests between a pair failed. It does not say the callee is at fault, which failure it was, or that it is happening now.
- An aborted request from fault injection is created by the caller's proxy, so the destination's metrics never see it.
- The Workloads and Services lists come from the API server, so they show workloads with no traffic. The graph does not.

**From [Validations, Badges And Cross-Checking](./course-03-validations-and-cross-checking.md):**

- Kiali's Istio Config view runs the same analyzers as `istioctl analyze` and reports the same `IST####` codes.
- The padlock is `connection_security_policy="mutual_tls"` on the metrics. It reports observed traffic, not a policy.
- Every picture in Kiali has a command behind it. Check that command before you act on a surprise.
- The method: Kiali graph, then the access log on the caller, then `istioctl proxy-config`, then `istioctl analyze`.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [An Empty Graph And A Red Badge](./labs/lab-01/README.md) | Validations, Badges And Cross-Checking | explain an empty graph, make it draw an edge, and clear every validation finding without removing the route |

If you skipped it, go back to it now. It is short.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. Kiali is <code>Running</code>, but the graph is empty. Name two causes that are not Kiali's fault.</summary>

No traffic in the selected time window, so there are no edges to draw. Or Prometheus is missing or unreachable, so Kiali has no metrics to build the graph from.
</details>

<details>
<summary>2. Which metric does Kiali turn into graph edges?</summary>

`istio_requests_total`. Kiali groups it by source and destination labels and draws each group with a rate above zero as an edge.
</details>

<details>
<summary>3. A canary problem is visible in the "versioned app" graph type. Why might it vanish in "app"?</summary>

"App" adds all versions together, so one red version and one green version become a single, mostly green node.
</details>

<details>
<summary>4. An edge from <code>tester</code> to <code>notification-service</code> is red. Is <code>notification-service</code> broken?</summary>

Not necessarily. The errors may come from the caller's own proxy, for example an injected abort or a `503` with a flag like `UH` or `NC`. The destination may never have seen those requests.
</details>

<details>
<summary>5. A healthy, meshed service with no traffic is missing from the graph. Where in Kiali can you still see it?</summary>

In the Workloads or Services list, which is built from Kubernetes objects, not metrics. Turning on Idle nodes in the graph also shows it.
</details>

<details>
<summary>6. Kiali shows a red validation badge. Which command gives the same findings in a terminal?</summary>

`istioctl analyze -n <namespace>`. Kiali uses the same analyzers and the same `IST####` codes.
</details>

<details>
<summary>7. Does a padlock on an edge prove the destination requires <code>STRICT</code> mTLS?</summary>

No. It shows that observed connections used mutual TLS. Under `PERMISSIVE`, a path can carry both mTLS and plain-text traffic.
</details>

<details>
<summary>8. You fixed a fault, but the edge is still red. Is the fix wrong?</summary>

Not yet known. The edge is a rate over a time window, and the window still holds the old failures. Wait a minute or two, or check the raw metrics.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-060-01
```

If `astrona list` also showed the mission, remove it the same way:

```sh
astrona destroy ats-016-lab-060-01
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with `astrona run`. It always starts clean, so nothing you broke carries over.

> *A tactical map is only as good as the signals behind it, and now you can read both.*
