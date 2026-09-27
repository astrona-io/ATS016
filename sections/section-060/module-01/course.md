# Troubleshoot With Kiali

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-060/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-060/module-01/playground
> astrona destroy ats-016-playground-060-01
> ```

Everything so far has been one proxy at a time. That is the right altitude once you know where to look, and the wrong one when the report is "something in checkout is slow" and there are forty services involved.

Kiali is the view from above: a graph of which service calls which, coloured by how badly it is going. The contrast that decides how much to trust it: **Kiali is a renderer, not a data source.** It stores nothing, instruments nothing, and measures nothing of its own — every number on the graph came from your proxies' metrics, and every validation came from the same analyzers `istioctl analyze` runs. That is exactly why a red edge is a real problem, and exactly why it is a place to start rather than an answer.

> Kiali renders istiod's view of the mesh, so a red edge or a broken-config badge is a real problem, not a rendering artefact.

## How this module is organised

1. **[Part 1 — What Kiali Is Built From](./course-01-what-kiali-is-built-from.md)** — the two data sources, how a metric series becomes a graph edge, and what each dependency's absence does to the picture.
2. **[Part 2 — Reading The Graph](./course-02-reading-the-graph.md)** — nodes, edges, the display options that matter, what a red edge states precisely, the time window, and why a healthy service can be invisible.
3. **[Part 3 — Validations, Badges And Cross-Checking](./course-03-validations-and-cross-checking.md)** — the Istio Config view against `istioctl analyze`, the security padlock against the metric behind it, and the method that uses Kiali as a locator rather than an oracle.

## Learning objectives

After this module you can:

- Name Kiali's two data sources and explain why it shows nothing without either.
- Describe how a request metric becomes a node and an edge in the graph.
- Choose the graph display options that answer a given question.
- Explain what a red edge states precisely, and what it does not.
- Explain why a running, healthy service can be absent from the graph entirely.
- Find the equivalent of `istioctl analyze` inside Kiali and say when to prefer each.
- Interpret the security padlock, and verify it against the metric it was computed from.
- Cross-check anything Kiali displays against the proxy data underneath it.

## Before you start

You need [section 050](../../section-050/module-01/course.md) — Kiali's graph is largely a rendering of `istio_requests_total`, and the security badge is the `connection_security_policy` label you already read from a proxy by hand in [module 050-02](../../section-050/module-02/course-03-fixing-and-proving-encryption.md).

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, the **Prometheus and Kiali addons** installed in `istio-system`, and the injected namespace **`kiali-demo`** containing `notification-service-v1` behind a Service on port 80 and a `tester` client pod with `curl`.

**About the dashboard.** Kiali is a web UI, and reaching it from your browser needs a port-forward your browser can actually connect to — which depends on how you are connected to this playground. Every checkpoint below therefore uses the command line, on the same data Kiali draws from. The module works either way, and you finish able to verify anything the UI claims.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it.

## Where this fits

Kiali is a starting point, not a conclusion. The practical sequence on an unfamiliar problem:

1. **Kiali graph** — which pair of workloads is failing, and how badly.
2. **Access log on the caller** ([050-01](../../section-050/module-01/course.md)) — the response flag, which names the layer.
3. **`istioctl proxy-config`** ([040-01](../../section-040/module-01/course.md)) — what the proxy was configured to do.
4. **`istioctl analyze`** ([010-01](../../section-010/module-01/course.md)) — whether the configuration was coherent in the first place.

Used that way it removes the hardest step, which is deciding where to point the tools. Used as an oracle it will mislead you, because a red edge is a symptom with at least half a dozen causes.
