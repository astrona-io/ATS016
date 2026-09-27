# Summarise A Workload With describe, Capture A Cluster With bug-report

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-010/module-02/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-02/playground
> astrona destroy ats-016-playground-010-02
> ```

You are handed a pod name and a complaint. Somewhere in the namespace there may be a `VirtualService`, a `DestinationRule`, a `PeerAuthentication` and an `AuthorizationPolicy`, written by four different people at four different times, and the only question that matters is: *which of them actually apply to this pod, and what do they add up to?*

Answering that by listing objects and reading YAML is slow and error-prone, because applicability depends on selectors, hosts and scope precedence rather than on what any single file says. This module covers the three tools for the three versions of that problem — one that summarises a workload's effective configuration, one that makes a proxy narrate a single decision, and one that packages the cluster so somebody else can answer the question instead.

> describe answers what applies to this pod; bug-report captures everything so somebody else can answer it.

## How this module is organised

1. **[Part 1 — What describe Resolves For One Workload](./course-01-what-describe-resolves.md)** — selector and scope precedence, how several policies merge into one effective answer, every section of the output, and the warnings at the bottom that are usually the finding.
2. **[Part 2 — Making A Proxy Narrate One Decision](./course-02-envoy-log-scopes-at-runtime.md)** — Envoy's admin interface, log scopes, raising `rbac` to `debug` at runtime without a restart, and reading the authorization verdict in the proxy's own words.
3. **[Part 3 — Capturing A Cluster With bug-report](./course-03-bug-report-and-handover.md)** — what the archive contains, the flags that keep it usable, its layout, and how to treat it as the sensitive artefact it is.

## Learning objectives

After this module you can:

- Explain how Istio decides which policies apply to a given workload, including scope precedence for `PeerAuthentication`.
- Run `istioctl x describe pod` and name what each section of its output tells you.
- State a workload's effective mTLS mode and the routes that apply to it from `describe` output alone.
- Recognise the two warnings `describe` most often produces, and say what each one silently breaks.
- Explain what Envoy log scopes are and why a scoped `debug` is different from a global one.
- Raise one log scope at runtime, read the resulting decision, and put the level back.
- Produce a `bug-report` archive scoped to a namespace and a time window, and list what it contains.
- Choose between `describe`, a scoped log level, and `bug-report` for a given situation.

## Before you start

You need to be comfortable with `kubectl`, and it helps to have [`istioctl analyze`](../module-01/course.md) fresh — `describe` is the natural second command, once analyze has told you the configuration is coherent and you still do not know what it *does* to a particular pod.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the injected namespace **`describe-demo`** containing:

- `notification-service-v1` — a Deployment labelled `version: v1`, behind the Service `notification-service` on port 80.
- `tester` — a client pod with `curl`.
- Four Istio objects that all apply to that one workload: a namespace-wide `PeerAuthentication` in `STRICT` mode, a `DestinationRule` defining subset `v1`, a `VirtualService` routing to it, and an `AuthorizationPolicy` that allows only `POST`.

Nothing here is broken. This module is about reading a working system, which is the harder skill.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it. Most of them need the pod's name, so set it once in the shell you will be working in:

```sh
export POD=$(kubectl -n describe-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
```

## Where this fits

These tools bracket an investigation rather than sitting in the middle of it. `istioctl analyze` ([module 1](../module-01/course.md)) asks whether the configuration is coherent; `describe` asks what that configuration means *for one workload*; a scoped log level asks the proxy to narrate one specific decision; `bug-report` stops asking and starts recording, for when the answer has to be found somewhere else or the cluster is about to be rebuilt.

Reach for `describe` first on any "this one service behaves oddly" report. It is the fastest orientation available for an unfamiliar workload, and it frequently ends the investigation before the deeper tools in sections 040 and 050 are needed.
