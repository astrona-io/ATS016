# Reading What The Analyzer Says

`istioctl analyze` reads every Istio object together and prints one message for each problem it finds. On a real cluster that list is long, and reading it top to bottom wastes time. This part shows how one message is built, what its severity really says, which codes are worth knowing by heart, and how the exit code of the command can do the reading for you in a build pipeline.

## One message, four fields

Every analyzer message has the same shape. If you read it field by field, a wall of text becomes a list of tasks:

```text
Error      [IST0101]   (VirtualService analyze-demo/notification)   Referenced host+subset ... not found: "notification-service+v3"
└ severity └ code      └ origin: the object it blames               └ message
```

- **Severity**: `Error`, `Warning` or `Info`.
- **Code**: a fixed `IST####` identifier for the kind of problem.
- **Origin**: the object, written as `<Kind> <name>.<namespace>`. When the analyzer reads a file instead of the cluster, it adds the file path and a line number.
- **Message**: the readable text. It is the only field that changes between Istio releases.

That last point is the practical reason to search by code, not by text. The wording of `IST0101` has changed more than once, and the number has not. Use the code in your searches, tickets and runbooks.

## Severity says what Istio will do, not how urgent it is

The three severities are easy to read as a priority order, but they are not one. They describe **what Istio will do with the object**. How much trouble you are in is a different question:

| Severity | Means | Does *not* mean |
| --- | --- | --- |
| `Error` | Istio cannot do what this object asks | that it is your most urgent problem |
| `Warning` | Istio will do something, and it is probably not what you meant | that it is safe to ignore |
| `Info` | A note about the configuration or the environment | that it does not matter |

A real example shows the difference. An `Error` on a `VirtualService` that no traffic uses costs you nothing today. An `IST0102` message, which is only `Info`, says a namespace has no sidecar injection label. New pods in that namespace then start without a sidecar proxy, so no Istio policy can be enforced for them. That is a complete failure with no error anywhere, reported at the lowest severity.

So read the `Error` messages to find what is broken, and read the rest to find what only looks like it works.

## The codes worth knowing by heart

There are dozens of codes. These five come up most often in troubleshooting, and each one has a typical symptom:

| Code | Severity | Meaning | Symptom you would otherwise chase |
| --- | --- | --- | --- |
| `IST0101` | `Error` | A referenced resource does not exist: host, subset, gateway or secret | `503` with no clear cause; a route to nothing |
| `IST0102` | `Info` | A namespace has no sidecar injection label | "my policy does nothing at all" |
| `IST0103` | `Warning` | A pod is missing the sidecar proxy | one workload ignores every Istio rule |
| `IST0109` | `Error` | Two `VirtualService` objects for the mesh define the same host | routing that changes when an unrelated object is edited |
| `IST0002` | `Warning` | The configuration uses a deprecated feature | works now, breaks at the next upgrade |

Two of the five are not `Error`s, and their configuration is entirely valid. That is typical of the whole tool: the most useful messages are often about configuration Istio accepts without complaint.

<!-- astrona:playground:renew -->

Run the analyzer on the playground namespace and look at the severity and code of each message:

```sh
istioctl analyze -n analyze-demo
```

You should see something like this (the last line, a link to the documentation, is left out):

```text
Error [IST0101] (VirtualService analyze-demo/notification) Referenced gateway not found: "missing-gateway"
Error [IST0101] (VirtualService analyze-demo/notification) Referenced host+subset in destinationrule not found: "notification-service+v3"
Warning [IST0132] (VirtualService analyze-demo/notification) one or more host [notification-service] defined in VirtualService analyze-demo/notification not found in Gateway analyze-demo/missing-gateway.
Error: Analyzers found issues when analyzing namespace: analyze-demo.
```

There are three messages, all on one object. The two `Error`s share one code, `IST0101`, for two different references that point at nothing. The `Warning`, `IST0132`, follows from the same missing gateway, so fixing the gateway reference clears it too. The origin names the object as `<namespace>/<name>`. Notice what is missing as well. There is no `IST0102`, because this namespace has the injection label. There is no `IST0103`, because both pods have a sidecar proxy. When the analyzer says nothing about a problem, it has checked for it and found none.

## Machine-readable output

The text format is for people at a terminal. The `-o json` flag prints the same messages as structured data. It also adds one field the text form does not print: the documentation address for each code.

Ask for JSON output:

```sh
istioctl analyze -n analyze-demo -o json
```

You should see something like this (shortened to one of the three messages):

```text
[
	{
		"code": "IST0101",
		"documentationUrl": "https://istio.io/v1.30/docs/reference/config/analysis/ist0101/?ref=istioctl-analyze",
		"level": "Error",
		"message": "Referenced host+subset in destinationrule not found: \"notification-service+v3\"",
		"origin": "VirtualService analyze-demo/notification"
	}
]
```

The fields are the same: `level` is the severity, then `code`, `origin` and `message`. The `documentationUrl` is built from the code and pinned to your Istio version, so it always explains the message you actually got. JSON output also makes the analyzer easy to script. For example, one `jq` command can count messages by code across every namespace, which shows whether a cluster has one repeated mistake or twenty different ones.

## Exit codes and the failure threshold

`istioctl analyze` exits with a non-zero code when it finds a message at or above a threshold. The default threshold is `Error`, so **`Warning` and `Info` messages do not fail the command**. In a build pipeline, an automated set of checks that runs before a change is merged or deployed, this means every `Warning` gets through.

The `--failure-threshold` flag moves that line. Set it to `Warning`, and a pod without a sidecar proxy fails your pipeline. Set it to `Info`, and a namespace without an injection label does too. Run the analyzer twice and print the exit code each time:

```sh
istioctl analyze -n analyze-demo >/dev/null 2>&1; echo "default threshold exit: $?"
istioctl analyze -n analyze-demo --failure-threshold Info >/dev/null 2>&1; echo "Info threshold exit: $?"
```

You should see something like:

```text
default threshold exit: 79
Info threshold exit: 79
```

Both exit codes are `79` here. `istioctl analyze` uses that code when it finds messages at or above the threshold, and this namespace has real `Error`s. The useful comparison comes after you fix them. With the `Error`s gone, the default threshold returns `0`, and a lower threshold still returns `79` if the namespace has a `Warning` or an `Info` message left. Choosing the threshold means deciding how much "valid but probably wrong" configuration you allow into the cluster.

> [!TIP]
> Choose the threshold on purpose instead of keeping the default. A common choice is `Warning` in a build pipeline and `Error` for a quick check by hand before a deploy.

The threshold applies to all codes at once. You cannot switch it off for a single code, so a message you have decided to accept keeps failing the pipeline until the configuration changes.

## Scope: the message you do not see

Analyzers check the objects in scope, and the default scope is one namespace. Without `-n`, that is the namespace of your current `kubectl` context. This leads to two problems. The first is a clean report on the wrong namespace: the command succeeded, but it answered a question you did not ask. The second is a misleading message about a relationship between namespaces. A `VirtualService` in the namespace `app` that binds to a `Gateway` in `istio-system` has one end out of scope, so analysing `app` alone can report the gateway as missing when it exists.

The `--all-namespaces` flag removes both problems, at the cost of a longer report. Use it when you are investigating, not when you are checking one change.

You can now read any analyzer message: its severity says what Istio will do, its code says what kind of problem it is, and its origin names the object. You also know that the default threshold and the default scope both hide messages unless you change them. What is still open is the input itself. So far the analyzer has only read the cluster, but it can also read files that were never applied.

## Common pitfalls

> [!WARNING]
> - **Reading only the `Error`s.** `IST0103` (a `Warning`) and `IST0102` (an `Info`) explain most "my policy has no effect" reports. Nothing is invalid; the policy applies to pods that have no sidecar proxy.
> - **Searching by message text.** The wording changes between releases, and the `IST####` code does not.
> - **Running analyze in the wrong namespace.** Without `-n`, it uses the namespace of your current context. Pass `-n`, or `--all-namespaces`.
> - **Trusting a one-namespace run on a relationship between namespaces.** A "missing gateway" message can come from the scope, not from a real fault.
> - **Keeping the default failure threshold in a pipeline.** `Error` lets every `Warning` and `Info` through, including a pod with no sidecar proxy.
