# Capturing A Cluster With bug-report

Astronaut, the dossier (`istioctl x describe pod`) and a raised log level both answer a question while you watch. Some problems do not allow that. They come and go, they sit in `istiod` (mission control) instead of in one proxy, the cluster is about to be rebuilt, or the person who can fix it has no access. `istioctl bug-report` is for those cases. It is the black box: it stops asking and starts recording.

## What it actually does

`bug-report` is not a single call. It walks the cluster and collects, for each selected target, the same things you would gather by hand:

| For | It collects |
| --- | --- |
| The control plane | `istiod` logs (including the previous container's log where there is one), `istiod`'s own configuration and environment, every Istio custom resource (`VirtualService`, `DestinationRule`, policies and so on), and cluster events |
| Each selected proxy | the full Envoy configuration dump (from `localhost:15000/config_dump`, the proxy's administration port), the proxy's statistics, the `istio-proxy` container log, and the pod spec |
| The cluster | Kubernetes version and node information |

The most important item is the **configuration dump**. It is the complete, live Envoy configuration for that proxy at the moment of capture: every order the communications officer holds. It is the same data `istioctl proxy-config` lets you read piece by piece.

Captured during the incident, it can be read later at your own pace. You cannot get that by running a command afterwards: by then the configuration has settled and the evidence is gone. That is the real case for the tool. It is not a convenience wrapper; it freezes state you cannot get back any other way.

## The flags that decide whether it is usable

Run with no flags, `bug-report` targets every proxy in the mesh. On a cluster with several hundred sidecars that is a long wait and an archive nobody can open. Three flags keep it in proportion:

| Flag | Effect | Use it for |
| --- | --- | --- |
| `--include` | limit to matching namespaces, deployments or pods | the namespace you are investigating |
| `--exclude` | drop matching targets (applied after `--include`) | a noisy sidecar in an otherwise relevant namespace |
| `--since` | limit how far back logs are collected | a known incident window |

`--include` and `--exclude` take a selector separated by slashes: `<namespace>/<deployment>/<pod>/<label>/<annotation>/<container>`. The parts at the end are optional. So `--include describe-demo` means the whole namespace, and `--include describe-demo/notification-service-v1` narrows it to one deployment.

`--since` is the one people forget. Without it you get the full stored log history of every selected pod. That is usually hours of unrelated traffic wrapped around the ten seconds that matter.

### Take a limited capture and look inside

This takes a minute or two even when limited, because the tool contacts each selected proxy's administration port in turn.

<!-- astrona:playground:renew -->

Capture the `describe-demo` planet for the last ten minutes, then list the first files in the archive:

```sh
istioctl bug-report --include describe-demo --since 10m
tar tzf bug-report.tar.gz | head -20
```

You should see something like:

```text
bug-report/cluster-context.txt
bug-report/istio-system/pods/istiod-7d4c9b8f4-k2m8x/logs/discovery.log
bug-report/describe-demo/pods/notification-service-v1-6c9f8b7d5-x2kqp/proxy/config_dump.json
bug-report/describe-demo/pods/notification-service-v1-6c9f8b7d5-x2kqp/logs/istio-proxy.log
bug-report/describe-demo/events.yaml
```

The layout mirrors the cluster: namespace, then pod, then the item. `istio-system` is there even though you only included `describe-demo`. The tool always collects the control plane, because a capture of the proxies without the mission control that gave them their orders is rarely enough to diagnose anything.

## Reading an archive you did not create

When an archive lands on your desk, the layout is your map. This order gets you to an answer fastest:

1. **`cluster-context.txt`**: versions and cluster shape. It shows whether you are looking at the Istio version you assumed.
2. **The proxy's `istio-proxy.log`**: the flight log, with access log lines and their response flags. The flag names the layer that failed.
3. **`config_dump.json` for that proxy**: what it was actually told to do at the time. It is large, so search it for the cluster or route name the log pointed at, instead of reading it.
4. **The `istiod` logs**: anything containing `reject`, plus push activity around the time of the incident.
5. **`events.yaml`**: restarts, evictions and failed webhook calls.

That is the same outside-in order as a live investigation, carried out on frozen evidence.

### Pull one proxy's configuration out of the archive

List the configuration dumps, extract them, and print the size of each:

```sh
tar tzf bug-report.tar.gz | grep config_dump
tar xzf bug-report.tar.gz --wildcards '*/config_dump.json'
find bug-report -name config_dump.json -exec sh -c 'echo "{}: $(wc -c < {}) bytes"' \;
```

You should see something like:

```text
bug-report/describe-demo/pods/notification-service-v1-6c9f8b7d5-x2kqp/proxy/config_dump.json
bug-report/describe-demo/pods/tester-6d9f7b8c5-hj4kz/proxy/config_dump.json
bug-report/describe-demo/pods/notification-service-v1-...-x2kqp/proxy/config_dump.json: 412873 bytes
```

That is several hundred kilobytes of JSON **per proxy**, for a namespace with two pods and almost no configuration. This number is the concrete reason `--include` matters: the same capture across a few hundred sidecars is measured in gigabytes.

## Treat the archive as sensitive

A bug report holds logs, full configurations and cluster details. Depending on your environment, that can include:

- your service layout and internal hostnames: a map of the system;
- certificate subject names and SPIFFE identities, the names printed on each ship's ID badge (not private keys, but a full list of who talks to whom);
- request paths, headers and anything your applications logged during the capture window;
- environment variables and mounted configuration references from pod specs.

None of that is secret on purpose, and all of it is useful to somebody attacking the cluster. Before you attach an archive to a public issue tracker or a vendor ticket, look inside it.

> [!TIP]
> Always pass `--include` and `--since`, even when you are in a hurry. A small archive you have reviewed is much easier to share than a large one you have not.

## When to reach for it

`bug-report` is the wrong first move and the right last one. Its cost is real: minutes of waiting, load on every selected proxy's administration port, and a file that needs careful handling. So use it when one of these is true:

- **You are handing the problem over**, to a vendor, another team or the next shift.
- **The evidence is about to disappear**: the cluster is being rebuilt, the pod is about to be recreated, or logs are kept only briefly.
- **The problem comes and goes.** Capture during an occurrence, read afterwards.
- **You need to compare two moments.** Capture now, capture after a change, and compare the configuration dumps.

For anything you can watch happening, `describe` and a scoped log level are faster and give you less to carry.

## Common pitfalls

> [!WARNING]
> - **Running it without `--include`.** It walks every proxy in the mesh: a long wait, heavy load, and an archive too large to hand to anyone.
> - **Leaving out `--since`.** You collect the full stored history of every selected pod and bury the window that matters.
> - **Sharing it without looking inside.** It holds your service layout, identities and whatever your applications logged. Review it before attaching it to anything public.
> - **Using it as a first diagnostic.** If you can reproduce the problem on demand, `describe` and a scoped log level answer faster and cost nothing.
> - **Forgetting it is a snapshot.** Nothing in the archive updates. A capture taken after the mesh settled shows a healthy system and proves nothing.

> *bug-report freezes the one thing you cannot go back for: every proxy's live configuration at the moment it was wrong.*
