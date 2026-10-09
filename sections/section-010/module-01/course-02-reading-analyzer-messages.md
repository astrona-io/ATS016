# Reading What The Analyzer Says

Astronaut, `istioctl analyze` is the pre-flight inspector: it reads every Istio object together and writes an inspection report. On a real cluster that report is long. This part turns it into a work queue: how one message is built, what its severity really claims, which codes are worth knowing by heart, and how to let the command's exit code do the reading for you in a pipeline.

## One message, three fields and a payload

Every finding has the same shape. Reading it in order turns a wall of text into a list of tasks:

```text
Error      [IST0101]   (VirtualService notification.analyze-demo)   Referenced host+subset ... not found: "notification-service+v3"
└ severity └ code      └ the object being blamed                    └ what is wrong
```

- **Severity**: `Error`, `Warning` or `Info`.
- **Code**: a stable `IST####` identifier, the inspector's warning code.
- **Origin**: the object, written as `<Kind> <name>.<namespace>`. When the analyzer read a file instead of the cluster, it adds the path and a line number.
- **Message**: the readable text. It is the only part that changes between Istio releases.

That last point is the practical reason to search by code, not by text. The wording of `IST0101` has changed more than once; the number has not. Your searches, tickets and runbooks should all use the code.

## Severity means valid, not important

The severities are easy to read as a priority order. They are not. They describe **what Istio will do with the object**, which is a different question from how much trouble you are in:

| Severity | Means | Does *not* mean |
| --- | --- | --- |
| `Error` | Istio cannot do what this object asks | that it is your most urgent problem |
| `Warning` | Istio will do something, and it is probably not what you meant | that it is safe to ignore |
| `Info` | A note about the configuration or the environment | that it is cosmetic |

Here is a real example of the difference. An `Error` on a `VirtualService` that no traffic uses costs you nothing today. A `Warning` that a namespace (a planet) carries mesh configuration without an injection label means **every policy on that planet applies to nothing**. No ship there has a communications officer (a sidecar proxy) to enforce it. That is a total, silent failure, reported one level below an `Error`.

So the rule is: read the Errors to find what is broken, and read the Warnings to find what is pretending to work.

## The codes worth knowing by heart

There are dozens of codes. These five carry most of the weight in troubleshooting, and each one has a typical symptom:

| Code | Severity (typical) | Meaning | Symptom you would otherwise chase |
| --- | --- | --- | --- |
| `IST0101` | `Error` | A referenced resource does not exist: host, subset, gateway or secret | `503` with no obvious cause; a route to nowhere |
| `IST0102` | `Warning` | A namespace has mesh configuration but no injection label | "my policy does nothing at all" |
| `IST0103` | `Info` | A pod has no sidecar | one workload ignoring every mesh rule |
| `IST0109` | `Warning` | Two `VirtualService` objects define the same host | routing that changes when an unrelated object is edited |
| `IST0106` | `Warning` | A deprecated field or API version is in use | works now, breaks at the next upgrade |

Three of those five are not Errors, and three describe configuration that is entirely valid. That is the shape of the whole tool: the interesting findings are usually the ones Istio is happy to serve.

### Sort a namespace's findings by severity

<!-- astrona:playground:renew -->

Run the analyzer on your playground's planet:

```sh
istioctl analyze -n analyze-demo
```

You should see something like:

```text
Error [IST0101] (VirtualService notification.analyze-demo) Referenced host+subset in destinationrule not found: "notification-service+v3"
Error [IST0101] (VirtualService notification.analyze-demo) Referenced gateway not found: "missing-gateway"
Error: Analyzers found issues when analyzing namespace: analyze-demo.
```

Two findings, one code, one object, two different references that point at nothing. Notice what is missing: no `IST0102`, because this namespace *is* labelled for injection, and no `IST0103`, because both pods have sidecars. When the analyzer stays quiet about something, it is telling you it checked.

## Machine-readable output

The text format is for people at a terminal. `-o json` gives you the same findings as structured data. It also carries one field the text form does not print: the documentation address for the code.

### See the same findings as JSON

Ask for JSON output:

```sh
istioctl analyze -n analyze-demo -o json
```

You should see something like:

```text
[
  {
    "code": "IST0101",
    "documentationUrl": "https://istio.io/v1.30/docs/reference/config/analysis/ist0101/",
    "level": "Error",
    "message": "Referenced host+subset in destinationrule not found: \"notification-service+v3\"",
    "origin": "VirtualService notification.analyze-demo"
  }
]
```

The output is shortened to one finding. It has the same three fields, `level`, `code` and `origin`, plus a documentation address built from the code and pinned to your Istio version. That is the fastest way to an explanation you did not have to remember, and another reason the code is the thing to carry around.

The JSON form also makes the analyzer scriptable. For example, counting findings by code across every namespace takes one `jq` command. It quickly shows whether a cluster's problems are one repeated mistake or twenty different ones.

## Exit codes, and turning this into a gate

`istioctl analyze` exits with a non-zero code when it finds something at or above a threshold. The default threshold is `Error`, so **Warnings do not fail the command**. That is the same gap as above, now with consequences for automation.

`--failure-threshold` moves the line. Set it to `Warning`, and a namespace with an injection-label problem starts failing your pipeline. Set it to `Info`, and a pod without a sidecar does too.

### Compare two thresholds on one namespace

Run the analyzer twice and print each exit code:

```sh
istioctl analyze -n analyze-demo >/dev/null 2>&1; echo "default threshold exit: $?"
istioctl analyze -n analyze-demo --failure-threshold Info >/dev/null 2>&1; echo "Info threshold exit: $?"
```

You should see something like:

```text
default threshold exit: 1
Info threshold exit: 1
```

Both are non-zero here, because this namespace has real `Error`s. The interesting run comes after you fix them: with the Errors gone, the default threshold returns `0` and a lower threshold may not. That difference is the whole decision in a build pipeline policy: how much "valid but probably wrong" you are willing to merge.

> [!TIP]
> Choose the threshold on purpose instead of keeping the default. Most teams want `Warning` in a build pipeline and `Error` in a quick check before a deploy.

A threshold is a blunt tool. You cannot switch it off for a single code, so a finding you have consciously accepted keeps failing the build until the configuration changes.

## Scope: the finding you do not see

Analyzers check the objects in scope, and the default scope is one namespace: your current context's namespace, unless you pass `-n`. That leads to two failures worth naming:

- **A clean report on the wrong namespace.** The command succeeded. It just answered a question you did not ask.
- **A misleading finding on a relationship between namespaces.** A `VirtualService` in `app` that binds to a `Gateway` in `istio-system` is one relationship with one object out of scope. Analysing `app` alone can report the gateway as missing when it exists.

`--all-namespaces` removes both problems at the cost of a longer report. It is the right choice when you are investigating, not checking one thing.

## Common pitfalls

> [!WARNING]
> - **Reading only the Errors.** `IST0102` (a Warning) and `IST0103` (an Info) explain most "my policy has no effect" reports. Nothing is invalid; the policy is simply applied to workloads that are not in the mesh.
> - **Searching by message text.** The wording changes between releases; the `IST####` code does not. Key your runbooks and searches on the code.
> - **Running analyze in the wrong namespace.** It looks at one namespace and silently uses your current context. Pass `-n`, or `--all-namespaces`.
> - **Assuming a one-namespace run sees both ends of a relationship between namespaces.** It does not, and the "missing gateway" finding that results comes from the scope, not from a fault.
> - **Keeping the default failure threshold in a pipeline.** `Error` lets every Warning through, including the ones that mean a whole namespace is outside the mesh.

> *Errors tell you what Istio refused to do; Warnings tell you what it did instead of what you meant.*
