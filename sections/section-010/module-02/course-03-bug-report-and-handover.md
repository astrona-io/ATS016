# Capturing A Cluster With bug-report

`istioctl x describe pod` and a raised log level both answer a question while you watch. Some problems do not allow that. They come and go, they sit in `istiod` instead of in one proxy, the cluster is about to be rebuilt, or the person who can fix the problem has no access to the cluster. `istioctl bug-report` is for those cases. It stops asking questions and starts recording: it collects the state of the control plane and of selected proxies into one archive that someone can read later.

## What it collects

`bug-report` is not one call. It walks the cluster and collects, for each selected target, the same things you would gather by hand, and writes them into a file named `bug-report.tar.gz`. Inside the archive, everything sits under a `bug-report/` folder with this layout in Istio 1.30:

| Path in the archive | What it holds |
| --- | --- |
| `versions` | The `istioctl` version and the Istio versions running in the cluster |
| `cluster/` | Cluster context, Kubernetes version, nodes, pods, events, the Istio custom resources (`crs`), the names of Secrets, and the Kubernetes resources of the included namespaces |
| `istio/<namespace>/<istiod pod>/` | The `istiod` log (`discovery.log`) and the output of `istiod`'s debug endpoints, such as `debug/syncz` and `debug/configz` |
| `proxies/<namespace>/<pod>/` | For each selected sidecar: its log (`istio-proxy.log`), its full Envoy configuration (`config_dump?include_eds`), and its `clusters`, `listeners`, `certs` and `stats/prometheus` |
| `analyze/` | The output of `istioctl analyze`, run at the end of the capture |

The most important item is the **configuration dump**. It is the complete Envoy configuration of that proxy at the moment of capture, read from the proxy's administration port on `localhost:15000`. It is the same data `istioctl proxy-config` shows you piece by piece.

A dump captured during an incident can be read later, at your own pace. You cannot get that by running a command afterwards, because by then the configuration may have changed and the evidence is gone. That is the real case for the tool: it freezes state you cannot get back any other way.

## The flags that keep it usable

Run with no flags, `bug-report` targets every proxy in the mesh. On a cluster with several hundred sidecar proxies, that is a long wait and an archive nobody can open. Three flags keep it in proportion:

| Flag | Effect | Use it for |
| --- | --- | --- |
| `--include` | Collect only from matching namespaces, Deployments, pods, labels, annotations or containers | the workloads you are investigating |
| `--exclude` | Drop matching targets, applied after `--include` | a noisy sidecar in an otherwise relevant namespace |
| `--duration` | Collect only log lines from this far back, for example `10m` | a known incident window |

`--include` and `--exclude` take a selector with up to six fields separated by slashes, in this order: namespace, Deployment, pod, label, annotation, container. Each field can hold a comma-separated list, and empty fields at the end can be left out. So `--include describe-demo` selects the whole namespace, and `--include describe-demo/notification-service-v1` selects one Deployment in it. You can pass `--include` more than once; a container is collected when it matches any of them.

The include filter also decides whether `istiod` is collected. `istiod` runs in `istio-system`, so a capture limited to `describe-demo` contains no control plane data. Add a second `--include istio-system/istiod` when the problem might sit in the control plane. `--duration` is the flag people forget. Without it you get the full stored log of every selected container, which is usually hours of unrelated traffic around the ten seconds that matter.

## Taking a limited capture

The command below captures every proxy in `describe-demo`, plus `istiod`, with the last ten minutes of logs. It takes a minute or two even when limited, because `istioctl` contacts each selected proxy's administration port in turn and runs `istioctl analyze` at the end.

<!-- astrona:playground:renew -->

Run it from a folder where you can write files:

```sh
istioctl bug-report --include describe-demo --include istio-system/istiod --duration 10m
```

The last line of the output names the file it wrote: `bug-report.tar.gz` in the current folder. The `--output-dir` flag writes it to another folder instead. Now list which pods the archive holds data for:

```sh
tar tzf bug-report.tar.gz | grep -E '^bug-report/(proxies|istio)/' | cut -d/ -f2-4 | sort -u
```

You should see three lines: `istio/istio-system/` followed by the `istiod` pod name, and `proxies/describe-demo/` followed by the `notification-service-v1` and `tester` pod names. The layout mirrors the cluster: namespace, then pod, then the files. No other namespace appears, because nothing else matched an `--include`.

## Reading an archive you did not create

When an archive lands on your desk, the layout is your map. This order gets you to an answer fastest:

1. **`versions`**: whether you are looking at the Istio version you assumed.
2. **The proxy's `istio-proxy.log`**: the access log lines and their response flags. A response flag is a short Envoy code that says why a request failed, and it names the layer that failed.
3. **The proxy's `config_dump?include_eds`**: what the proxy was told to do at that moment. It is large, so search it for the cluster or route name the log pointed at instead of reading it.
4. **The `istiod` log**: anything containing `reject`, and push activity around the time of the incident.
5. **`cluster/events`**: restarts, evictions and failed webhook calls.

That is the same outside-in order as a live investigation, applied to frozen evidence. To see how large one proxy's configuration is, extract the archive into its own folder and measure each dump:

```sh
mkdir -p bug-report-extract
tar xzf bug-report.tar.gz -C bug-report-extract
find bug-report-extract -name 'config_dump*' -exec wc -c {} +
```

Each dump is often several hundred kilobytes of JSON, even for a namespace with two pods and almost no Istio configuration. That number is the concrete reason `--include` matters: the same capture across a few hundred sidecar proxies grows to gigabytes.

## Treat the archive as sensitive

A bug report holds logs, full proxy configurations and cluster details. Depending on your environment, that includes your service layout and internal hostnames, and the workload identities in every certificate, which together show who talks to whom. It also includes request paths, headers and anything your applications logged during the window, and the environment variables and configuration references from pod specs. By default it records only the names of Secrets. The `--full-secrets` flag adds their contents, so never use it on an archive you plan to share.

None of that is secret on purpose, and all of it helps someone who attacks the cluster. Before you attach an archive to a public issue tracker or a vendor ticket, look inside it.

> [!TIP]
> Always pass `--include` and `--duration`, even when you are in a hurry. A small archive you have reviewed is much easier to share than a large one you have not.

## When to use it

`bug-report` is the wrong first step and the right last one. It costs minutes of waiting, load on every selected proxy's administration port, and a file that needs careful handling. Use it when you hand the problem over to a vendor, another team or the next shift. Use it when the evidence is about to disappear: the cluster is being rebuilt, the pod is about to be recreated, or logs are kept only briefly. Use it when a problem comes and goes, so you can capture during one occurrence and read afterwards. And use it to compare two moments: capture now, capture after a change, and compare the configuration dumps.

For anything you can watch happening, `describe` and a scoped log level are faster and give you less to carry.

You now know what `istioctl bug-report` collects and where each item sits in the archive. You know how `--include` and `--duration` keep the capture small, that `istiod` is only collected when an `--include` matches it, and that the archive must be reviewed before it is shared. Together with `describe` and a log scope, you have three tools for three situations: what applies, why one decision happened, and what the whole system looked like at one moment.

## Common pitfalls

> [!WARNING]
> - **Running it without `--include`.** It walks every proxy in the mesh: a long wait, heavy load, and an archive too large to hand to anyone.
> - **Leaving out `--duration`.** You collect the full stored log of every selected container and bury the window that matters.
> - **Expecting `istiod` in a capture limited to one namespace.** Add `--include istio-system/istiod` when the control plane may be involved.
> - **Sharing it without looking inside, or with `--full-secrets`.** It holds your service layout, identities and whatever your applications logged.
> - **Forgetting it is a snapshot.** Nothing in the archive updates. A capture taken after the problem cleared shows a healthy system and proves nothing.

## Your mission: Capture A Limited bug-report Archive

You can now take a `bug-report` capture that holds exactly the workloads that matter, plus the control plane. The graded lab asks you to hand a platform team an archive of one failing workload and `istiod`, without the proxies of any other pod in the cluster.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-010-02
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-02/labs/lab-02
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-010/module-02/labs/lab-02
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-010-02-02
astrona start ats-016-playground-010-02
```
