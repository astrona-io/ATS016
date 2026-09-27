# Part 3 — Capturing A Cluster With bug-report

> Prerequisite: [Part 2 — Making A Proxy Narrate One Decision](./course-02-envoy-log-scopes-at-runtime.md). Next: [the module landing page](./course.md), then [section 020](../../section-020/module-01/course.md).

Every tool so far answers a question while you watch. Some problems do not allow that: they are intermittent, they are in `istiod` rather than in one proxy, the cluster is about to be rebuilt, or the person who can fix it has no access. `istioctl bug-report` is for those — it stops asking and starts recording.

## What it actually does

`bug-report` is not a single API call. It walks the cluster and collects, for each selected target, the same artefacts you would gather by hand:

```text
  for the control plane:
      istiod logs                  (kubectl logs, including --previous where available)
      istiod's own config and env
      the Istio custom resources   (every VirtualService, DestinationRule, policy, ...)
      cluster events

  for each selected proxy:
      the full Envoy config dump   (localhost:15000/config_dump — Part 2's admin port)
      the proxy's stats
      the istio-proxy container log
      the pod spec

  plus:
      cluster version and node information
```

The important entry is the **config dump**. It is the complete, live Envoy configuration for that proxy at the moment of capture — the same data [section 040](../../section-040/module-01/course.md) teaches you to query in pieces with `istioctl proxy-config`. Captured during the incident, it can be read afterwards at leisure, which is the one thing you cannot do by re-running a command later: by then the configuration has converged and the evidence is gone.

That is the real argument for the tool. It is not a convenience wrapper; it is a way to freeze state that is otherwise unrecoverable.

## The flags that decide whether it is usable

Run bare, `bug-report` targets every proxy in the mesh. On a cluster with several hundred sidecars that is a long wait and an archive nobody can open. Three flags keep it proportionate:

| Flag | Effect | Use it for |
| --- | --- | --- |
| `--include` | restrict to matching namespaces / deployments / pods | the namespace you are investigating |
| `--exclude` | drop matching targets (applied after `--include`) | a noisy sidecar in an otherwise relevant namespace |
| `--since` | limit how far back logs are collected | a known incident window |

`--include` and `--exclude` take a slash-separated selector — `<namespace>/<deployment>/<pod>/<label>/<annotation>/<container>` — with trailing parts optional, so `--include describe-demo` means the whole namespace and `--include describe-demo/notification-service-v1` narrows to one deployment.

`--since` is the one people forget. Without it you get the full retained log history of every selected pod, which is usually hours of unrelated traffic wrapped around the ten seconds that matter.

> [!TIP]
> **Try it — a scoped capture, and what is inside it**
>
> This takes a minute or two even scoped, because it contacts every selected proxy's admin interface in turn.
>
> ```sh
> istioctl bug-report --include describe-demo --since 10m
> tar tzf bug-report.tar.gz | head -20
> ```
>
> Expect something like:
>
> ```text
> bug-report/cluster-context.txt
> bug-report/istio-system/pods/istiod-7d4c9b8f4-k2m8x/logs/discovery.log
> bug-report/describe-demo/pods/notification-service-v1-6c9f8b7d5-x2kqp/proxy/config_dump.json
> bug-report/describe-demo/pods/notification-service-v1-6c9f8b7d5-x2kqp/logs/istio-proxy.log
> bug-report/describe-demo/events.yaml
> ```
>
> The layout mirrors the cluster: namespace, then pod, then artefact. Note that `istio-system` is present despite `--include describe-demo` — control plane state is always collected, because a data plane capture without the control plane that configured it is rarely enough to diagnose anything.

## Reading an archive you did not create

The layout above is the navigation guide. When an archive lands on you, the order that gets to an answer fastest is:

1. **`cluster-context.txt`** — versions and cluster shape. Establishes whether you are looking at the Istio version you assumed.
2. **The proxy's `istio-proxy.log`** — access log lines with response flags ([section 050](../../section-050/module-01/course.md)), which name the failing layer.
3. **`config_dump.json` for that proxy** — what it was actually configured to do at the time. Large; search it for the cluster or route name the log implicated rather than reading it.
4. **`istiod` logs** — anything containing `reject`, plus push activity around the incident timestamp.
5. **`events.yaml`** — restarts, evictions, failed webhook calls.

That is the same outside-in order as a live investigation, executed on frozen evidence.

> [!TIP]
> **Try it — pulling one proxy's configuration out of the archive**
>
> ```sh
> tar tzf bug-report.tar.gz | grep config_dump
> tar xzf bug-report.tar.gz --wildcards '*/config_dump.json'
> find bug-report -name config_dump.json -exec sh -c 'echo "{}: $(wc -c < {}) bytes"' \;
> ```
>
> Expect something like:
>
> ```text
> bug-report/describe-demo/pods/notification-service-v1-6c9f8b7d5-x2kqp/proxy/config_dump.json
> bug-report/describe-demo/pods/tester-6d9f7b8c5-hj4kz/proxy/config_dump.json
> bug-report/describe-demo/pods/notification-service-v1-...-x2kqp/proxy/config_dump.json: 412873 bytes
> ```
>
> Several hundred kilobytes of JSON **per proxy**, for a namespace with two pods and almost no configuration. That number is the concrete reason `--include` matters: the same capture across a few hundred sidecars is an archive measured in gigabytes.

## Treat the archive as sensitive

A bug report contains logs, full configurations and cluster metadata. Depending on your environment that can include:

- your service topology and internal hostnames — a map of the system;
- certificate subject names and SPIFFE identities (not private keys, but a complete list of who talks to whom);
- request paths, headers and anything your applications logged during the capture window;
- environment variables and mounted config references from pod specs.

None of that is secret by intent, and all of it is useful to somebody attacking the cluster. Before attaching one to a public issue tracker or a vendor ticket, look inside it — and prefer `--since` and `--include` to keep the window and the blast radius small. A capture you have reviewed is a much easier thing to share than one you have not.

## When to reach for it

`bug-report` is the wrong first move and the right last one. Its cost is real — minutes of wall clock, load on every selected proxy's admin interface, an artefact that needs handling — so the trigger should be one of:

- **You are handing the problem over.** To a vendor, to another team, to the next shift.
- **The evidence is about to disappear.** The cluster is being rebuilt, the pod is about to be recreated, the log retention window is short.
- **The problem is intermittent.** Capture during an occurrence, read afterwards.
- **You need to compare two moments.** Capture now, capture after a change, diff the config dumps.

For anything you can watch happening, `describe` and a scoped log level are faster and produce less to carry.

> [!WARNING]
> **Pitfalls with bug-report**
>
> - **Running it unscoped.** Without `--include` it walks every proxy in the mesh: a long wait, heavy load, and an archive too large to hand anyone.
> - **Omitting `--since`.** You collect the full retained history of every selected pod and bury the window that matters.
> - **Sharing it without looking inside.** It contains topology, identities and whatever your applications logged. Review before attaching it to anything public.
> - **Using it as a first diagnostic.** If you can reproduce the problem on demand, `describe` plus a scoped log level answers faster and costs nothing.
> - **Forgetting it is a snapshot.** Nothing in the archive updates. A capture taken after the mesh reconverged shows a healthy system and proves nothing.

> *bug-report freezes the one thing you cannot go back for: every proxy's live configuration at the moment it was wrong.*

## Reference

- `istioctl bug-report --help` — the selector syntax for `--include` / `--exclude`, plus `--timeout` and the output path flag.
- [istioctl bug-report](https://istio.io/latest/docs/reference/commands/istioctl/#istioctl-bug-report) — the command reference, including the full list of collected artefacts.
- [Reporting a bug](https://github.com/istio/istio/blob/master/CONTRIBUTING.md) — what the Istio maintainers expect an archive to be accompanied by; a good template even for an internal handover.
- [Envoy config dump](https://www.envoyproxy.io/docs/envoy/latest/operations/admin#get--config_dump) — the structure of the largest file in the archive, worth skimming before you first open one.
