# Walking The Chain

The response flag has narrowed the failure to one stage. This part confirms it with the tool that reads the whole configuration at once, `istioctl analyze`. Then it walks the chain by hand, because the manual walk is what you need on the day the analyzer has nothing to say.

## The fast path first

Before you follow anything by hand, spend two seconds on `istioctl analyze`. It reads every Istio object in scope together and reports the references that do not resolve, so for a broken reference it is often the whole answer. Run it on the playground namespace:

<!-- astrona:playground:renew -->

```sh
istioctl analyze -n fivezerothree-demo
```

You should see something like:

```text
Error [IST0101] (VirtualService fivezerothree-demo/notification) Referenced host+subset in destinationrule not found: "notification-service+v2"
Error: Analyzers found issues when analyzing namespace: fivezerothree-demo.
See https://istio.io/v1.30/docs/reference/config/analysis for more information about causes and resolutions.
```

The code `IST0101` means a referenced resource does not exist. The message names both halves of the problem: the `VirtualService` refers to `notification-service+v2`, and no `DestinationRule` defines that subset. That is the same statement the `NC` flag made from the proxy's side, reached on its own from the configuration.

Two separate sources agreeing is worth noticing. The analyzer read the objects stored in Kubernetes; the flag came from a proxy's behaviour at run time. When they disagree, for example a clean analyzer run with an `NC` flag, you have learned something else. The configuration is coherent, but the proxy still runs older configuration, so the problem is delivery from `istiod`, not the configuration itself.

## Why walk the chain anyway

The analyzer runs a fixed set of checks. It will not tell you that a subset exists but its labels match no pod, which is valid configuration with an empty cluster. It will not tell you that endpoints exist but this proxy has stopped using them, or that a proxy still runs configuration from before your fix. It also knows nothing about a problem no analyzer was written for. The chain works in all of those cases, because it reads what the proxy actually runs. The analyzer is the shortcut; the chain is the skill.

The first link is the route. It is Istio's translation of your `VirtualService`, and the cluster name it produces is the exact string the next command needs. Pull the cluster names out of the `tester` proxy's routes:

```sh
istioctl proxy-config routes deploy/tester -n fivezerothree-demo -o json \
  | grep '"cluster"' | grep notification
```

You should see something like:

```text
        "cluster": "outbound|80|v2|notification-service.fivezerothree-demo.svc.cluster.local",
```

Read the four fields: outbound, port 80, subset **`v2`**, and the fully qualified name. The route stage worked: the rule matched, it produced a destination, and the proxy did exactly what the `VirtualService` asked. The subset name is the first thing that is provably wrong, and it is an *input* to the next stage rather than a fault in this one.

## Does that cluster exist?

A cluster for a subset exists only if a `DestinationRule` defines that subset, so ask the proxy what it actually has. List the `tester` proxy's clusters for `notification-service`:

```sh
istioctl proxy-config cluster deploy/tester -n fivezerothree-demo | grep notification
```

You should see something like:

```text
notification-service.fivezerothree-demo.svc.cluster.local      80        -          outbound      EDS              notification.fivezerothree-demo
notification-service.fivezerothree-demo.svc.cluster.local      80        v1         outbound      EDS              notification.fivezerothree-demo
```

There are two clusters: the one without a subset, and `v1`. There is no `v2` row. The route names a destination that does not exist in this proxy's configuration at all, which is what `NC` said, now confirmed from the configuration side. The last column names the `DestinationRule` that would have had to define it. At this point the diagnosis is complete. The endpoint stage is still worth checking once, because it teaches the difference the choice of fix depends on.

## Two different kinds of empty

An empty endpoint list can mean two quite different things. Ask for the endpoints of the `v2` cluster and of the `v1` cluster:

```sh
istioctl proxy-config endpoints deploy/tester -n fivezerothree-demo \
  --cluster "outbound|80|v2|notification-service.fivezerothree-demo.svc.cluster.local"
istioctl proxy-config endpoints deploy/tester -n fivezerothree-demo \
  --cluster "outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local"
```

You should see something like:

```text
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.8:8084     HEALTHY     OK                outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local
```

`v2` returns only the header line, but read *why* it is empty: there is no such cluster to have endpoints. `v1` has a healthy pod that has been waiting there all along. Nothing was ever wrong with the workload; the route named a destination that does not exist. The output looks the same for two different states, and telling them apart matters:

| State | Listed by `proxy-config cluster`? | Endpoints | Flag |
| --- | --- | --- | --- |
| **No cluster** | no | empty (nothing to ask about) | `NC` |
| **Empty cluster** | yes | empty | `UH` |

The endpoint command alone cannot tell them apart, which is why the cluster check is not optional. The cluster check answers *does it exist*; the endpoint check answers *does it have anything*. Mixing the two up is how people fix the wrong end.

## The chain as a habit

Put together, the walk is one short procedure, and each command uses a name the previous one produced:

```text
   flag NC/UH
       │
       ▼
   istioctl analyze -n <ns>                      ← 2 seconds, often the whole answer
       │
       ▼
   proxy-config routes ... -o json | grep cluster
       │   └─ copy the EXACT cluster name
       ▼
   proxy-config cluster ... --fqdn <host>
       │   ├─ name absent  → NC. A missing subset or host. Fix the reference.
       │   └─ name present → continue
       ▼
   proxy-config endpoints ... --cluster "<name>"
           ├─ empty        → UH. Selector, readiness, or subset labels.
           └─ populated    → check STATUS and OUTLIER CHECK
```

That is what makes it a chain rather than a search. It is also why you copy the cluster name exactly, quoted and with empty fields kept: the next command matches it character by character.

You now know the exact missing link: the route names the cluster `outbound|80|v2|...`, and the proxy has no such cluster, while the `v1` cluster has a healthy pod. You also know that a missing cluster and an empty cluster look alike at the endpoint stage. The open question is which end of the reference to change, because both edits make the analyzer quiet and only one makes the requests succeed.

## Common pitfalls

> [!WARNING]
> - **Skipping the cluster check and going straight to endpoints.** An empty endpoint list looks the same whether the cluster is missing or only empty, and those need different fixes.
> - **Retyping the cluster name.** Copy it from the route output. `--cluster` matches exactly, empty fields included, and `|` needs quoting in a shell.
> - **Asking the destination proxy.** This failure lives in the client's configuration; the destination never saw the request.
> - **Trusting a clean analyzer run to mean the proxy agrees.** The analyzer reads the stored objects; the chain reads the proxy. A disagreement points at delivery from `istiod`.
> - **Treating the analyzer's silence as "no problem".** It runs a fixed set of checks; subset labels that match no pod are valid configuration it will not report.
