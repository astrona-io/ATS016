# Read The Proxy Configuration

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-040/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/module-01/playground
> astrona destroy ats-016-playground-040-01
> ```

By the time you reach this module in a real investigation you have established three things: the configuration is coherent, the proxy received it, and the workload is in the mesh. The request still does the wrong thing. There is nowhere left to look except inside Envoy.

That sounds worse than it is. Envoy handles a request in four stages, in a fixed order, and `istioctl proxy-config` has one subcommand per stage. The contrast that makes this tractable: **`proxy-status` asks whether configuration arrived; `proxy-config` asks what it became.** Every request failure lives at exactly one of the four stages, and knowing which stage a symptom belongs to is most of the diagnosis.

> Listener → route → cluster → endpoint: every request failure lives at exactly one of those four steps.

## How this module is organised

1. **[Part 1 — Capture And Listeners](./course-01-capture-and-listeners.md)** — how traffic gets into the proxy at all, the iptables redirection, ports 15001 and 15006, and what a listener does with a connection.
2. **[Part 2 — Routes](./course-02-routes.md)** — route configurations named by port, virtual host selection by `Host` header, and why the tabular output hides what you need.
3. **[Part 3 — Clusters And Endpoints](./course-03-clusters-and-endpoints.md)** — the four-field cluster name, discovery types, what an endpoint list means, and the difference between `HEALTHY` and `OUTLIER CHECK: OK`.
4. **[Part 4 — The Inbound Direction, Certificates And Method](./course-04-inbound-secrets-and-method.md)** — the receiving proxy's configuration, where server-side policy is enforced, reading a proxy's certificates, and the four-stage walk as a procedure.

## Learning objectives

After this module you can:

- Explain how a pod's traffic reaches its sidecar, and why the application needs no change.
- Name Envoy's four request-handling stages and the `istioctl proxy-config` subcommand that shows each.
- Say what ports 15001, 15006, 15021 and 15090 are for.
- Read an Istio cluster name and say what its four fields mean, including an empty subset field.
- Narrow a query with `--fqdn`, `--port`, `--name` and `--cluster` instead of reading a full dump.
- Tell an inbound listener and cluster from an outbound one, and explain which side of a connection each belongs to.
- Explain why server-side policy is invisible in the client's configuration.
- Map a symptom — a `404`, a `503`, a policy that appears not to apply — onto the stage that most likely produced it.
- Inspect the certificates a proxy is holding and read their validity.

## Before you start

You need to be comfortable with `kubectl`, and you should have met `istioctl proxy-status` in [module 030-02](../../section-030/module-02/course.md) — the `CDS` / `LDS` / `EDS` / `RDS` columns there are the same four stages this module inspects one by one.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the injected namespace **`proxycfg-demo`** containing:

- `notification-service-v1` — a Deployment labelled `version: v1`, behind the Service `notification-service` on port 80, targeting container port 8084.
- `tester` — a client pod with `curl`.
- A `DestinationRule` defining subset `v1` and a `VirtualService` with a header match and a default route, both pointing at `v1`.

Nothing is broken. This module reads a working proxy, because you cannot recognise a wrong configuration until you know what a right one looks like.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it.

## Where this fits

This is question three of the outside-in sequence, and the last one that can be answered from configuration alone. [Section 050](../../section-050/module-01/course.md) picks up where it ends, with what the proxy actually *did* to a specific request — the access log and its response flags. The two are complements: `proxy-config` shows intent as the proxy understands it, the access log shows outcome.

The four stages also recur outside this module. [Module 040-02](../module-02/course.md) walks them under time pressure on a live `503`, and the cluster naming convention from Part 3 is what makes an Envoy-language error message translate back into the Istio object you need to edit.
