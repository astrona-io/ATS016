# Part 2 — Reading What The Analyzer Says

> Prerequisite: [Part 1 — What The API Server Checks, And What It Cannot](./course-01-admission-and-the-analysis-gap.md). Next: [Part 3 — Choosing The Right Analysis Source](./course-03-analysis-sources-and-the-fix-loop.md).

The analyzer's output is a list of findings, and on a real cluster it is a long one. This part turns that list into a work queue: how one message is built, what its severity actually claims, which codes are worth knowing by heart, and how to make the command's exit status do the reading for you in a pipeline.

## One message, three fields and a payload

Every finding has the same shape, and reading it in order is what turns a wall of text into a set of tasks:

```text
Error      [IST0101]   (VirtualService notification.analyze-demo)   Referenced host+subset ... not found: "notification-service+v3"
└ severity └ code      └ the object being blamed                    └ what is wrong
```

- **Severity** — `Error`, `Warning` or `Info`.
- **Code** — a stable `IST####` identifier.
- **Origin** — the object, as `<Kind> <name>.<namespace>`. When the analyzer read a file rather than the cluster it appends the path and a line number.
- **Message** — human-readable, and the only part that changes between releases.

That last point is the practical reason to navigate by code rather than by text: the wording of `IST0101` has been reworded more than once, the number has not. Search engines, issue trackers and your own runbooks should all key on the code.

## Severity means valid, not important

The severities are easy to misread as a priority ordering. They are not. They describe **what Istio will do with the object**, which is a different axis from how much trouble you are in:

| Severity | Means | Does *not* mean |
| --- | --- | --- |
| `Error` | Istio cannot do what this object asks | that it is your most urgent problem |
| `Warning` | Istio will do something, and it is probably not what you meant | that it is safe to ignore |
| `Info` | An observation about the configuration or the environment | that it is cosmetic |

The asymmetry is sharp enough to be worth stating as a rule. An `Error` on a `VirtualService` nobody routes through costs you nothing today. A `Warning` that a namespace carries mesh configuration without an injection label means **every policy in that namespace applies to nothing** — a total, silent failure of intent, reported one rung down from the weight arithmetic in Part 1.

So: read the Errors to find what is broken, and read the Warnings to find what is pretending to work.

## The codes worth memorising

There are dozens. These five carry most of the weight in troubleshooting, and each one has a characteristic symptom:

| Code | Severity (typical) | Meaning | Symptom you would otherwise chase |
| --- | --- | --- | --- |
| `IST0101` | `Error` | A referenced resource does not exist — host, subset, gateway or secret | `503` with no obvious cause; a route to nowhere |
| `IST0102` | `Warning` | A namespace has mesh config but no injection label | "my policy does nothing at all" |
| `IST0103` | `Info` | A pod has no sidecar | one workload ignoring every mesh rule |
| `IST0109` | `Warning` | Two `VirtualService` objects define the same host | routing that changes when an unrelated object is edited |
| `IST0106` | `Warning` | A deprecated field or API version is in use | works now, breaks at the next upgrade |

Three of those five are not Errors, and three of them describe configuration that is entirely valid. That is the shape of the whole tool: the interesting findings are usually the ones Istio is perfectly happy to serve.

> [!TIP]
> **Try it — sorting a namespace's findings by severity**
>
> ```sh
> istioctl analyze -n analyze-demo
> ```
>
> Expect something like:
>
> ```text
> Error [IST0101] (VirtualService notification.analyze-demo) Referenced host+subset in destinationrule not found: "notification-service+v3"
> Error [IST0101] (VirtualService notification.analyze-demo) Referenced gateway not found: "missing-gateway"
> Error: Analyzers found issues when analyzing namespace: analyze-demo.
> ```
>
> Two findings, one code, one object, two distinct dangling references. Note what is absent: no `IST0102`, because this namespace *is* labelled for injection, and no `IST0103`, because both pods have sidecars. An analyzer that stays quiet about something is telling you it checked.

## Machine-readable output

The text format is for humans at a terminal. `-o json` gives you the same findings as structured data, and it carries one field the text form does not print — the documentation URL for the code.

> [!TIP]
> **Try it — the same findings, structured**
>
> ```sh
> istioctl analyze -n analyze-demo -o json
> ```
>
> Expect something like:
>
> ```text
> [
>   {
>     "code": "IST0101",
>     "documentationUrl": "https://istio.io/v1.30/docs/reference/config/analysis/ist0101/",
>     "level": "Error",
>     "message": "Referenced host+subset in destinationrule not found: \"notification-service+v3\"",
>     "origin": "VirtualService notification.analyze-demo"
>   }
> ]
> ```
>
> Same three fields — `level`, `code`, `origin` — plus a URL that is generated from the code and pinned to your Istio version. That is the fastest route to an explanation you did not have to remember, and it is why the code is the thing to carry around.

The JSON form is also what makes the analyzer scriptable. Counting findings by code across every namespace, for example, is one `jq` away — a useful way to see whether a cluster's problems are one repeated mistake or twenty different ones.

## Exit codes, and turning this into a gate

`istioctl analyze` exits non-zero when it finds something at or above a threshold. The default threshold is `Error`, which means **Warnings do not fail the command** — the same asymmetry as above, now with consequences for automation.

`--failure-threshold` moves the line. Set it to `Warning` and a namespace with an injection-label problem starts failing your pipeline; set it to `Info` and an uninjected pod does.

> [!TIP]
> **Try it — the same namespace, two thresholds**
>
> ```sh
> istioctl analyze -n analyze-demo >/dev/null 2>&1; echo "default threshold exit: $?"
> istioctl analyze -n analyze-demo --failure-threshold Info >/dev/null 2>&1; echo "Info threshold exit: $?"
> ```
>
> Expect something like:
>
> ```text
> default threshold exit: 1
> Info threshold exit: 1
> ```
>
> Both non-zero here, because this namespace has genuine `Error`s. The interesting experiment is the one you run after [Part 3](./course-03-analysis-sources-and-the-fix-loop.md) fixes them: with the Errors gone, the default threshold returns `0` and a lower threshold may not. That difference is the whole design decision in a CI policy — how much "valid but probably wrong" you are prepared to merge.

Two practical notes on using it that way. First, pick the threshold deliberately rather than inheriting the default; most teams want `Warning` in CI and `Error` in a pre-deploy smoke check. Second, a threshold is a blunt instrument — there is no per-code suppression, so a finding you have consciously accepted will keep failing the build until the configuration changes.

## Scope: the finding you do not see

Analyzers evaluate the objects in scope, and the default scope is a single namespace — your current context's namespace unless you pass `-n`. That produces two failure modes worth naming:

- **A clean report on the wrong namespace.** The command succeeded, it just answered a question you did not ask.
- **A misleading finding on a cross-namespace relationship.** A `VirtualService` in `app` binding to a `Gateway` in `istio-system` is a two-object relationship with one object out of scope. Analysing `app` alone can report the gateway as missing when it exists.

`--all-namespaces` removes both problems at the cost of a longer report, and it is the right default when you are investigating rather than checking one thing.

> [!WARNING]
> **Pitfalls in reading the output**
>
> - **Reading only the Errors.** `IST0102` and `IST0103` are a Warning and an Info respectively, and between them they explain most "my policy has no effect" reports. Nothing is invalid — the policy is simply being applied to workloads that are not in the mesh.
> - **Navigating by message text.** The wording changes between releases; the `IST####` code does not. Key your runbooks and searches on the code.
> - **Running analyze in the wrong namespace.** It is namespace-scoped and silently defaults to your current context. Pass `-n` explicitly, or `--all-namespaces`.
> - **Assuming a namespace-scoped run sees both ends of a cross-namespace reference.** It does not, and the resulting "missing gateway" finding is an artefact of scope rather than a fault.
> - **Leaving the default failure threshold in CI.** `Error` lets every Warning through, including the ones that mean an entire namespace is outside the mesh.

> *Errors tell you what Istio refused to do; Warnings tell you what it did instead of what you meant.*

## Reference

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — the full `IST####` catalogue, one page per code with causes and resolutions. This is the page `documentationUrl` points into.
- `istioctl analyze --help` — `--failure-threshold`, `--output`, `--all-namespaces`, `--suppress`, and the file-handling flags Part 3 uses.
- [Common problems](https://istio.io/latest/docs/ops/common-problems/) — symptom-first index, useful when you have a behaviour and no finding to explain it.
