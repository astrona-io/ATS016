# Walking The Chain

Astronaut, the response flag has narrowed the failure to one stage. This part confirms it with the tool that reads the whole configuration at once, the analyzer. Then it walks the chain by hand, because the manual walk is what you need on the day the analyzer has nothing to say.

## The fast path first

Before following anything by hand, spend two seconds on `istioctl analyze`, the pre-flight inspector that reads every Istio object together and reports the ones that point at nothing. For a dangling reference it is often the whole answer.

<!-- astrona:playground:renew -->

### Run the analyzer

Analyze the playground's planet:

```sh
istioctl analyze -n fivezerothree-demo
```

You should see something like:

```text
Error [IST0101] (VirtualService notification.fivezerothree-demo) Referenced host+subset in destinationrule not found: "notification-service+v2"
```

The warning code `IST0101` (referenced resource not found) names both halves of the problem in one line. The `VirtualService` refers to `notification-service+v2`, and no `DestinationRule` defines that subset. The `host+subset` notation is the analyzer's way of saying the pair does not resolve. That is the same statement the `NC` flag made from the proxy's side, reached on its own from the configuration.

Two separate sources agreeing is worth noticing. The analyzer read the objects stored in Kubernetes; the flag came from a proxy's behaviour at run time. When they disagree, for example a clean analyzer run with an `NC` flag, you have learned something else. The configuration is coherent, but the proxy is still running something older, so the problem is delivery from `istiod` (mission control), not the configuration.

## Why walk the chain anyway

The analyzer runs a fixed set of checks. It will not tell you:

- that a subset exists but its labels match no pod (valid configuration, empty cluster);
- that endpoints exist but this particular proxy has pushed them out;
- that a proxy is still running configuration from before your fix;
- anything about a problem no analyzer was written for.

The chain works in all of those cases, because it reads what the proxy is actually running. The analyzer is the shortcut; the chain is the skill.

## Step one: which cluster does the route name?

The route is Istio's translation of your `VirtualService`, the flight plan. The cluster name it produces is the exact string the next command needs.

### See the name the route hands on

Pull the cluster names out of the test ship's routes:

```sh
istioctl proxy-config routes deploy/tester -n fivezerothree-demo -o json \
  | grep '"cluster"' | grep notification
```

You should see something like:

```text
        "cluster": "outbound|80|v2|notification-service.fivezerothree-demo.svc.cluster.local",
```

Read the four fields: outbound, port 80, subset **`v2`**, and the fully qualified name. This tells you the route stage worked: the rule matched, it produced a destination, and the proxy did exactly what the `VirtualService` asked. The subset name is the first thing that is provably wrong, and it is an *input* to the next stage rather than a fault in this one.

## Step two: does that cluster exist?

A cluster for a subset exists only if a `DestinationRule` defines that subset. Ask the proxy what it actually has.

### See the clusters that exist

List the test ship's clusters for `notification-service`:

```sh
istioctl proxy-config cluster deploy/tester -n fivezerothree-demo | grep notification
```

You should see something like:

```text
notification-service.fivezerothree-demo.svc.cluster.local   80  -    outbound  EDS  notification.fivezerothree-demo
notification-service.fivezerothree-demo.svc.cluster.local   80  v1   outbound  EDS  notification.fivezerothree-demo
```

There are two clusters: the one without a subset, and `v1`. There is no `v2` row. The route names a destination that does not exist in this proxy's configuration at all, which is exactly what `NC` said, now confirmed from the configuration side. The last column names the `DestinationRule` that would have had to define it.

At this point the diagnosis is complete, and you could stop. Step three is worth doing once anyway, because it teaches the difference that the choice of fix depends on.

## Step three: two different kinds of empty

An empty endpoint list can mean two quite different things. This step shows both side by side.

### See the two empty answers

Ask for the endpoints of the `v2` cluster and of the `v1` cluster:

```sh
istioctl proxy-config endpoints deploy/tester -n fivezerothree-demo \
  --cluster "outbound|80|v2|notification-service.fivezerothree-demo.svc.cluster.local"
istioctl proxy-config endpoints deploy/tester -n fivezerothree-demo \
  --cluster "outbound|80|v1|notification-service.fivezerothree-demo.svc.cluster.local"
```

You should see something like:

```text
ENDPOINT   STATUS   OUTLIER CHECK   CLUSTER

ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.12:8084     HEALTHY     OK                outbound|80|v1|notification-service...
```

`v2` returns an empty table, but read *why* it is empty: there is no such cluster to have endpoints. `v1` has a healthy pod that has been waiting there all along. Nothing was ever wrong with the workload; the route was addressed to a destination that does not exist.

The output looks the same for two different states, and telling them apart matters:

| State | Listed by `proxy-config cluster`? | Endpoints | Flag |
| --- | --- | --- | --- |
| **No cluster** | no | empty (nothing to ask about) | `NC` |
| **Empty cluster** | yes | empty | `UH` |

The endpoint command alone cannot tell them apart, which is why step two is not optional. Step two answers *does it exist*; step three answers *does it have anything*. Mixing the two up is how people fix the wrong end.

## The chain as a habit

Put together, the walk is one short procedure. Each command uses a name the previous one produced:

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

That is what makes it a chain rather than a search. It is also why copying the cluster name exactly, quoted and with empty fields kept, is not fussiness: it is how the chain works.

## Common pitfalls

> [!WARNING]
> - **Skipping the cluster step and going straight to endpoints.** An empty endpoint list looks the same whether the cluster is missing or merely empty, and those need different fixes.
> - **Retyping the cluster name.** Copy it from the route output. `--cluster` matches exactly, empty fields included, and `|` needs quoting in a shell.
> - **Asking the destination proxy.** This failure lives in the client's configuration; the destination never saw the request.
> - **Trusting a clean analyzer run to mean the proxy agrees.** The analyzer reads the stored objects; the chain reads the proxy. A disagreement points at delivery, and it is a finding, not a contradiction.
> - **Treating the analyzer's silence as "no problem".** It runs a fixed set of checks; subset labels that match no pod are valid configuration it will not flag.

> *The chain is one name at a time: the route produces it, the cluster confirms it, the endpoints fill it. Every empty answer means something different depending on which step produced it.*
