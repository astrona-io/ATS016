# Read Envoy Access Logs And Response Flags

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-050/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-01/playground
> astrona destroy ats-016-playground-050-01
> ```

Every request through the mesh passes through at least two proxies, and each one writes a line about it. That line records what the proxy did, what the upstream did, how long it took, and — in a short code near the front — *why the request ended the way it did*.

The contrast with [section 040](../../section-040/module-01/course.md) is the whole reason both exist: **`proxy-config` shows what a proxy is configured to do; the access log shows what it actually did.** Configuration explains intent, the log records outcome, and a great many incidents are a disagreement between the two. Learning to read that short code is the highest-value skill in this course: it turns "the service is returning errors" into "the circuit breaker rejected it" or "the route timeout fired" or "the request never left the client pod", before you have opened a single YAML file.

> The response flag names the failure: UH, UF, UC, UO, UT, NR and DC each mean something specific.

## How this module is organised

1. **[Part 1 — Turning Logging On, And Scoping It](./course-01-enabling-and-scoping-logs.md)** — the mesh-wide setting, the `Telemetry` resource, providers, filtering by request, and why volume is the thing that decides your design.
2. **[Part 2 — The Anatomy Of A Line](./course-02-anatomy-of-a-log-line.md)** — every field in the default format, the six that answer most questions, and `RESPONSE_CODE_DETAILS`.
3. **[Part 3 — Flags, And Which Proxy Wrote The Line](./course-03-flags-and-which-proxy.md)** — the full flag taxonomy as a model rather than a list, and reading a pair of logs to establish whether a request crossed the network.
4. **[Part 4 — Producing Each Failure On Demand](./course-04-producing-each-failure.md)** — a timeout, a circuit breaker rejection, a routing miss and an authorization denial, each created deliberately and identified from its log alone.

## Learning objectives

After this module you can:

- Enable access logging mesh-wide or for one namespace, and say which mechanism to use when.
- Scope logging with a `Telemetry` resource, including filtering to failed requests only.
- Name the fields of the default access log format and locate the response flag.
- Read `RESPONSE_CODE_DETAILS` and say when it matters more than the flag.
- Map the common flags to their causes, and recognise what a bare `-` means.
- Determine from a pair of logs whether a request ever reached its destination.
- Reproduce a timeout, a circuit breaker rejection, a routing miss and an authorization denial.
- Explain why an authorization denial is only explained on the destination proxy.
- Summarise a window of traffic by flag to see which failure dominates.

## Before you start

You need [section 040](../../section-040/module-01/course.md): the four stages and the `istioctl proxy-config` subcommands. Several flags in this module name a stage directly, and the cluster naming convention appears in every log line.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the injected namespace **`accesslog-demo`** containing `notification-service-v1` behind a Service on port 80, a `tester` client pod with `curl`, and a `Telemetry` object scoping access logs to the namespace.

Part 4 applies configuration that deliberately breaks traffic — a fault injection, a tight circuit breaker, a deny-all policy. Each is removed or replaced by a later step, and all of it is confined to this namespace.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it.

## Where this fits

The access log is the fastest first move in a live incident, ahead of everything else in this course, because it partitions the problem in one command:

1. **Flag `-` with an error status** → the application answered. Leave Istio alone.
2. **A `U*` flag on the client** → the request did not get where it was going. Follow the chain in [section 040](../../section-040/module-01/course.md).
3. **Both proxies logged** → it arrived. Look at destination-side policy and `RESPONSE_CODE_DETAILS`.

[Module 050-02](../module-02/course.md) then takes one signature from this module — `UF` on the client with nothing on the server — and works it end to end as an mTLS mismatch.
