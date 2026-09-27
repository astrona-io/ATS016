# Part 2 — Walking The Chain

> Prerequisite: [Part 1 — Who Answered With 503](./course-01-who-answered-with-503.md). Next: [Part 3 — Choosing The Fix, And The Other Cause](./course-03-choosing-the-fix.md).

The flag has narrowed the failure to one stage. This part confirms it with the tool that reads the whole configuration at once, then walks the chain by hand — because the manual walk is what you will need on the day the analyzer has nothing to say.

## The fast path first

Before following anything by hand, spend two seconds on the analyzer. For a dangling reference it is frequently the entire answer.

> [!TIP]
> **Try it — the fast path**
>
> ```sh
> istioctl analyze -n fivezerothree-demo
> ```
>
> Expect something like:
>
> ```text
> Error [IST0101] (VirtualService notification.fivezerothree-demo) Referenced host+subset in destinationrule not found: "notification-service+v2"
> ```
>
> `IST0101` names both halves of the problem in one line: the `VirtualService` references `notification-service+v2`, and no `DestinationRule` defines that subset. The `host+subset` notation is the analyzer's way of saying the pair does not resolve — which is the same statement the `NC` flag made from the data plane side, arrived at independently from the configuration.

Two independent sources agreeing is worth noticing rather than skipping past. The analyzer read objects in etcd; the flag came from a proxy's runtime behaviour. When those two disagree — a clean analyze with a `NC` flag — you have learned something else: the configuration is coherent and the proxy is running something older, which is a delivery problem ([module 030-02](../../section-030/module-02/course.md)) rather than a configuration one.

## Why walk the chain anyway

The analyzer's coverage is a fixed set of checks. It will not tell you:

- that a subset exists but its labels match no pod (valid configuration, empty cluster);
- that endpoints exist but this particular proxy has ejected them;
- that a proxy is running configuration from before your fix;
- anything at all about a mesh whose problem no analyzer was written for.

The chain works in all of those cases, because it reads what the proxy is actually running. The analyzer is the shortcut; the chain is the skill.

## Step one: which cluster does the route name?

The route is Istio's translation of your `VirtualService`, and the cluster name it produces is the exact string the next command needs.

> [!TIP]
> **Try it — the name the route hands on**
>
> ```sh
> istioctl proxy-config routes deploy/tester -n fivezerothree-demo -o json \
>   | grep '"cluster"' | grep notification
> ```
>
> Expect something like:
>
> ```text
>         "cluster": "outbound|80|v2|notification-service.fivezerothree-demo.svc.cluster.local",
> ```
>
> Read the four fields: outbound, port 80, subset **`v2`**, that FQDN. Note what this tells you about the route stage — it worked. The rule matched, it produced a destination, and the proxy did exactly what the `VirtualService` asked. The subset name is the first verifiably wrong thing in the investigation, and it is an *input* to the next stage rather than a fault in this one.

## Step two: does that cluster exist?

A cluster for a subset exists only if a `DestinationRule` defines that subset ([module 040-01 Part 3](../module-01/course-03-clusters-and-endpoints.md)). Ask the proxy what it actually has.

> [!TIP]
> **Try it — the clusters that actually exist**
>
> ```sh
> istioctl proxy-config cluster deploy/tester -n fivezerothree-demo | grep notification
> ```
>
> Expect something like:
>
> ```text
> notification-service.fivezerothree-demo.svc.cluster.local   80  -    outbound  EDS  notification.fivezerothree-demo
> notification-service.fivezerothree-demo.svc.cluster.local   80  v1   outbound  EDS  notification.fivezerothree-demo
> ```
>
> Two clusters: the subsetless one, and `v1`. There is no `v2` row. The route names a destination that does not exist in this proxy's configuration at all — which is precisely what `NC` said, now confirmed from the configuration side. The `DESTINATION RULE` column names the object that would have had to define it.

At this point the diagnosis is complete and you could stop. Step three is worth doing anyway, once, because it teaches the distinction that the next module's fix depends on.

## Step three: two different kinds of empty

> [!TIP]
> **Try it — the two different empty answers**
>
> ```sh
> istioctl proxy-config endpoints deploy/tester -n fivezerothree-demo \
>   --cluster "outbound|80|v2|notification-service.fivezerothree-demo.svc.cluster.local"
> istioctl proxy-config endpoints deploy/tester -n fivezerothree-demo \
>   --cluster "outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local"
> ```
>
> Expect something like:
>
> ```text
> ENDPOINT   STATUS   OUTLIER CHECK   CLUSTER
> 
> ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
> 10.244.0.12:8084     HEALTHY     OK                outbound|80|v1|notification-service...
> ```
>
> `v2` returns an empty table — but read *why* it is empty: there is no such cluster to have endpoints. `v1` has a healthy pod that has been waiting there all along. Nothing was ever wrong with the workload; the route was addressed to a destination that does not exist.

The output looks identical for two quite different states, and telling them apart matters:

| State | Cluster listed by `proxy-config cluster`? | Endpoints | Flag |
| --- | --- | --- | --- |
| **No cluster** | no | empty (nothing to query) | `NC` |
| **Empty cluster** | yes | empty | `UH` |

The endpoint command alone cannot distinguish them, which is why step two is not optional. Step two answers *does it exist*; step three answers *does it have anything*. Conflating the two is how people fix the wrong end — the subject of [Part 3](./course-03-choosing-the-fix.md).

## The chain as a habit

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

Each command consumes a name the previous one produced. That is what makes it a chain rather than a search, and it is why copying the cluster name exactly — quoted, with empty fields intact — is not fussiness but the mechanism.

> [!WARNING]
> **Pitfalls while walking the chain**
>
> - **Skipping the cluster step and going straight to endpoints.** An empty endpoint list looks the same whether the cluster is missing or merely empty, and those need different fixes.
> - **Retyping the cluster name.** Copy it from the route output. `--cluster` matches exactly, empty fields included, and `|` needs quoting in a shell.
> - **Querying the destination proxy.** This failure lives in the client's configuration; the destination never saw the request.
> - **Trusting a clean analyze run to mean the proxy agrees.** The analyzer reads etcd, the chain reads the proxy. A disagreement is a delivery problem, and it is a finding rather than a contradiction.
> - **Treating the analyzer's silence as "no problem".** Its coverage is a fixed set of checks; subset labels matching no pod is valid configuration it will not flag.

> *The chain is one name at a time: the route produces it, the cluster confirms it, the endpoints populate it — and every empty answer means something different depending on which step produced it.*

## Reference

- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — the `proxy-config` subcommands with worked output.
- [IST0101 — referenced resource not found](https://istio.io/latest/docs/reference/config/analysis/ist0101/) — the analyzer page for the fast path.
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — subsets and their label selectors, the object that makes a cluster exist.
- `istioctl proxy-config cluster --help` — `--fqdn`, `--port`, `--subset` and `--direction` for narrowing on a real cluster.
