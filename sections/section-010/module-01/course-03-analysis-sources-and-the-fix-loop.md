# Part 3 — Choosing The Right Analysis Source

> Prerequisite: [Part 2 — Reading What The Analyzer Says](./course-02-reading-analyzer-messages.md). Next: [the module landing page](./course.md), then [section 020](../../section-020/module-01/course.md).

An analyzer runs over a configuration set. Which set is a choice you make on the command line, and it changes the answers — a file that looks broken in isolation is fine on top of the cluster, and a cluster that looks clean may be about to receive a change nothing has checked. This part covers the three sources, the lighter `validate` command, and the verification discipline that turns a finding into a fix you can defend.

## Three ways to assemble the set

```text
  A.  istioctl analyze -n <ns>
      set = { objects in the cluster }
      "is what is running coherent?"

  B.  istioctl analyze -n <ns> file.yaml
      set = { objects in the cluster } overlaid with { objects in file.yaml }
      "would this change be coherent?"        ← the pre-merge check

  C.  istioctl analyze --use-kube=false file.yaml
      set = { objects in file.yaml }
      "is this file coherent on its own?"     ← the CI check, with no cluster
```

Form **B** is the one most worth building a habit around, and the one people discover last. It answers the question you actually have when you are about to apply something: not "is this file self-contained" but "does this file make sense *given what is already there*". A new `VirtualService` referencing a subset the cluster already defines passes B and fails C.

Form **C** is what runs in a pipeline, where there is no cluster to consult. Its limitation follows directly from the set definition: anything the file legitimately refers to elsewhere is, as far as the analyzer can tell, missing. Expect false alarms about hosts, gateways and secrets defined outside the file. That makes C appropriate for a self-contained bundle of manifests and misleading for a single fragment.

> [!TIP]
> **Try it — catching a mistake before it exists in the cluster**
>
> Write a pair of objects to a file, then analyse the file alone:
>
> ```sh
> cat > /tmp/proposed.yaml <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: DestinationRule
> metadata:
>   name: notification
>   namespace: analyze-demo
> spec:
>   host: notification-service
>   subsets:
>     - name: v1
>       labels:
>         version: v1
> ---
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: notification
>   namespace: analyze-demo
> spec:
>   hosts:
>     - notification-service
>   http:
>     - route:
>         - destination:
>             host: notification-service
>             subset: v3
> EOF
> istioctl analyze --use-kube=false /tmp/proposed.yaml
> ```
>
> Expect something like:
>
> ```text
> Error [IST0101] (VirtualService notification.analyze-demo /tmp/proposed.yaml:14) Referenced host+subset in destinationrule not found: "notification-service+v3"
> Error: Analyzers found issues when analyzing <file>.
> ```
>
> The same `IST0101` that cost you a `503`, found on a file with nothing deployed. Note the origin field: with a file to read, the analyzer can give you a **line number**, which it cannot do for an object in etcd. Keep `/tmp/proposed.yaml`; the next checkpoint reuses it.

Both objects are in that file, so the finding is real rather than an artefact of scope — the `DestinationRule` is right there, defining `v1` and not `v3`. That is what a good C-form input looks like: complete enough that a missing reference means something.

## analyze against validate

There is a second, lighter command, and the distinction between them is exactly the distinction from [Part 1](./course-01-admission-and-the-analysis-gap.md): one document, or a set.

`istioctl validate -f file.yaml` answers only the single-document question — is this well-formed, are the fields real, do the enums hold. It never contacts the cluster and never looks at a second object. It is, in effect, the admission webhook's check run locally, before you ever submit.

| | `istioctl validate` | `istioctl analyze` |
| --- | --- | --- |
| Question answered | Is the document well-formed? | Does the configuration set make sense together? |
| Needs a cluster | No | Optional (`--use-kube=false` to skip) |
| Sees other objects | No | Yes |
| Catches a misspelled field | Yes | Yes |
| Catches weights summing to 120 | Yes | Yes |
| Catches a missing subset | **No** | Yes |
| Catches a namespace without injection | No | Yes |

The practical placement: `validate` in an editor hook or a pre-commit hook, where speed matters and there is no cluster; `analyze` before you apply and whenever traffic is wrong.

> [!TIP]
> **Try it — the same broken file through the lighter check**
>
> ```sh
> istioctl validate -f /tmp/proposed.yaml
> ```
>
> Expect something like:
>
> ```text
> validation succeed
> ```
>
> The file that just produced an `Error` is, on its own terms, perfectly valid YAML addressed to the right schema with every field in place. That single line is the entire reason `analyze` exists as a separate command.

## Fixing: which end of a dangling reference to change

An `IST0101` says a reference does not resolve. There are always two ways to make a reference resolve — create the target, or stop referencing it — and they are not equally correct.

In this namespace the `VirtualService` names `subset: v3` and a gateway that does not exist. Only `version: v1` pods are deployed, so:

- **Adding a `v3` subset to the `DestinationRule`** would make the analyzer quiet and the traffic still fail. A subset whose labels match no pod produces a cluster with no endpoints — you would convert a clear "no such cluster" failure into a murkier "no healthy upstream" one. [Section 040](../../section-040/module-02/course.md) is about telling those two apart; do not manufacture the second on purpose.
- **Routing to `v1` and dropping the gateway reference** matches what is actually deployed, and the gateway is not needed because nothing here is exposed outside the mesh.

The rule generalises: make the reference true *in the direction that matches reality*, and check what is really deployed before inventing a target.

> [!TIP]
> **Try it — clean analysis, then real traffic**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: notification
>   namespace: analyze-demo
> spec:
>   hosts:
>     - notification-service
>   http:
>     - route:
>         - destination:
>             host: notification-service
>             subset: v1
> EOF
> istioctl analyze -n analyze-demo
> kubectl -n analyze-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
> ```
>
> Expect something like:
>
> ```text
> virtualservice.networking.istio.io/notification configured
> ✔ No validation issues found when analyzing namespace: analyze-demo.
> 200
> ```
>
> Two independent confirmations, and you need both. Either one alone can lie: a clean analyze with a `503` means the configuration is coherent but has not reached the proxy; a `200` with analyzer errors means you are getting lucky on a path that does not touch the broken object.

## Why "one change, then re-check" is not pedantry

The fix above was a single object edit, verified twice. That discipline exists because of a specific property of this tool: **the analyzer reports findings, not causes.** Two findings can share one cause, and one mistake can silence a finding while creating another.

Change two things and you lose the ability to attribute the outcome. On a graded exam that costs you the marks for a fix you cannot demonstrate; in production it costs you the knowledge of which change to roll back at 03:00.

The loop, then:

```text
   analyze  ──▶  pick ONE finding  ──▶  change ONE object  ──▶  analyze again
        ▲                                                            │
        └──────────────── plus: send a real request ◀────────────────┘
```

And once a namespace is quiet, widen the scope before declaring it healthy. Mesh problems cross namespace boundaries constantly — a `Gateway` lives in `istio-system`, the `VirtualService` that binds to it lives with the application — and a namespace-scoped run only ever saw one side of that.

> [!TIP]
> **Try it — the whole mesh at once**
>
> ```sh
> istioctl analyze --all-namespaces
> ```
>
> Expect something like:
>
> ```text
> ✔ No validation issues found when analyzing all namespaces.
> ```
>
> On a real cluster this is rarely silent, and that is fine — the goal is not zero findings, it is knowing which findings you have consciously decided to live with. Anything you cannot explain is still an open question.

> [!WARNING]
> **Pitfalls in choosing a source and applying a fix**
>
> - **Expecting `--use-kube=false` to be quiet on a fragment.** With no cluster context, legitimate references to objects defined elsewhere are reported as missing. That mode is for self-contained bundles and CI, not for spot-checking one file out of ten.
> - **Using `validate` where you needed `analyze`.** `validate` cannot see a second object, so it will pass every cross-object mistake in this module.
> - **Fixing a dangling reference by creating the target without checking it exists in reality.** A subset matching no pods trades a loud failure for a quiet one.
> - **Fixing several findings in one apply.** When the symptom clears you will not know which change mattered, and an unverifiable fix is not a fix.
> - **Stopping at a clean analyze.** It proves coherence, not delivery and not behaviour. Send a request, and if that still fails, move to `istioctl proxy-status`.
> - **Declaring a namespace healthy without `--all-namespaces`.** Half of a cross-namespace relationship is invisible from inside one namespace.

> *Choose the set before you read the findings: the cluster answers "is this broken", the file answers "would this break it".*

## Reference

- [Using the analyzer](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-analyze/) — the canonical write-up of the three source forms, including analysing a whole directory of manifests.
- `istioctl validate --help` — the short command, and the `-f -` form that reads from standard input for editor integration.
- `istioctl analyze --help` — `--use-kube`, `--all-namespaces`, `--failure-threshold` and `--suppress` in one place.
- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — look up any code a widened run turns up.
