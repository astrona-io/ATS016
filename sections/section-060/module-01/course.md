# Troubleshoot With Kiali

Astronaut, so far you have looked at one ship at a time. That works once you know where to look. It does not work when the report says "something is slow" and forty services are involved.

Kiali is the tactical map in mission control: every ship and every signal path on one screen, with red where it hurts. Here is the key fact about it: **Kiali draws pictures, it does not collect data.** It stores nothing and measures nothing of its own. Every number on its map comes from the metrics your sidecar proxies (the communications officers on each ship) record. Every warning comes from the same checks that `istioctl analyze` runs. So a red line on the map is a real problem. It is also only a place to start looking, not an answer.

## Learning objectives

After this module you can:

- Name Kiali's two data sources and explain why it shows nothing without either one.
- Describe how a request metric becomes a node and an edge in the graph.
- Choose the graph display options that answer a given question.
- Explain exactly what a red edge says, and what it does not say.
- Explain why a running, healthy service can be missing from the graph.
- Find the same findings as `istioctl analyze` inside Kiali, and say when to use each.
- Explain the security padlock, and check it against the metric it comes from.
- Check anything Kiali shows against the proxy data underneath it.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels, `kubectl exec` and `kubectl logs`.
- **Istio basics.** What a sidecar proxy is, and what a `VirtualService` does.
- **Istio's request metric.** Every sidecar counts the requests it handles in a metric called `istio_requests_total`. Each count carries labels: who called, who was called, the response code, and `connection_security_policy`, which says whether the connection used mutual TLS (mTLS, the secret handshake where both ships show their ID badges before they talk).

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** already installed (the `demo` profile) and `istioctl` ready to use. In the `istio-system` namespace it also runs two add-ons: **Prometheus**, the telemetry recorder that collects the metrics, and **Kiali**, the tactical map.

The planet (namespace) **`kiali-demo`** has sidecar injection switched on. On it you find:

| Workload | What it does |
| --- | --- |
| `notification-service-v1` | The app, behind the Service (beacon) `notification-service` on port `80`. It answers `["EMAIL"]` |
| `tester` | Your test ship, with `curl`. Every test signal is sent from here |

No traffic flows when the playground starts, so the Kiali graph starts empty. That is on purpose.

Kiali is a web page. Whether your browser can reach it depends on how you are connected to the playground. So every hands-on step in this module also has a command-line form that reads the same data Kiali draws from.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts, in order

1. [What Kiali Is Built From](./course-01-what-kiali-is-built-from.md): the two data sources, how a metric becomes an edge, and what happens to the picture when one source is missing.
2. [Reading The Graph](./course-02-reading-the-graph.md): nodes, edges, the display options that matter, what a red edge says, and why a healthy service can be invisible.
3. [Validations, Badges And Cross-Checking](./course-03-validations-and-cross-checking.md): the Istio Config view next to `istioctl analyze`, the padlock next to its metric, and a method that uses Kiali to find the problem, not to explain it.
4. [Wrap-Up: Mission Debrief](./course-04-wrap-up.md): what you learned, your mission, and cleaning up.

## Why this matters

On an unfamiliar problem, the hardest step is deciding where to point your tools. Kiali answers that in one look: which pair of workloads is failing, and how badly. Then the access log, `istioctl proxy-config` and `istioctl analyze` tell you why. Used that way, Kiali saves you time. Used as the final answer, it misleads you, because a red edge can have many causes.
