# Part 3 — The Route Table Is The Ground Truth

> Prerequisite: [Part 2 — One Host, Two Owners](./course-02-host-ownership-and-merging.md). Next: [the module landing page](./course.md), then [section 030](../../section-030/module-01/course.md).

Two objects, merged in an order nobody chose, one of them shadowing its own rule: reading YAML can no longer tell you what will happen to a request. Only the proxy knows. This part asks it, reads the answer, applies the two-part fix, and establishes the verification standard the rest of the course uses.

## Asking a proxy what it holds

`istioctl proxy-config routes <pod-or-deployment> -n <ns>` fetches the **route configuration the named proxy is currently running** — Envoy's own structure, in Envoy's own order, after every merge `istiod` performed.

Underneath, the command reads `localhost:15000/config_dump` on that proxy (the admin interface from [module 010-02 Part 2](../../section-010/module-02/course-02-envoy-log-scopes-at-runtime.md)) and filters it to the routes section. Two consequences: the answer is live rather than desired state, and it is per-proxy — two workloads can legitimately hold different tables for the same host.

The subcommands are named after Envoy's building blocks: `routes`, `cluster`, `endpoint`, `listener`, `secret`, `log`. The chain they describe — a **listener** accepts, a **route** chooses a **cluster**, a cluster resolves to **endpoints** — is [section 040](../../section-040/module-01/course.md)'s subject. Here only the route step matters, because a header match either happens there or nowhere.

`--name 80` selects the route configuration named after the port, which is the naming from [Part 1](./course-01-virtualservice-to-route-table.md).

> [!TIP]
> **Try it — what the proxy will really do**
>
> ```sh
> istioctl proxy-config routes deploy/tester -n conflict-demo \
>   --name 80 -o json | grep -E '"name"|"cluster"|"exact_match"|"prefix"' | head -20
> ```
>
> Expect something like:
>
> ```text
>   "name": "80",
>         "cluster": "outbound|80|v1|notification-service.conflict-demo.svc.cluster.local",
>         "cluster": "outbound|80|v1|notification-service.conflict-demo.svc.cluster.local",
> ```
>
> Read the cluster names rather than counting lines: the `v1` subset appears twice, `v2` appears nowhere, and no `exact_match` on a header appears at all. That is the decisive evidence. The route to `v2` is not misconfigured or mismatched — as far as this proxy is concerned it does not exist. JSON details differ between Istio versions; the cluster names are the stable part to read.

The tabular form (`without -o json`) is quicker but collapses every rule's match to `/*`, which hides precisely the field you need here. Its `VIRTUAL SERVICE` column is still worth a glance: it names the object that produced each route, and an empty value means Istio generated a default route from the Service alone — a precise way to discover your object is not being applied.

Whenever the proxy's table disagrees with the YAML in front of you, **the YAML is not the whole story**: some other object contributed to what the proxy received. That sentence is the reason this command exists, and in this namespace the other object is the one Part 2 identified.

## The fix has two halves

The two causes need two changes, and doing them one at a time is what lets you attribute each symptom.

**Half one — restore single ownership.** Delete the duplicate claimant so exactly one object describes the host. Until this is done, any ordering you impose can be reshuffled by the merge.

**Half two — order the surviving object's rules.** Specific match first, unconditional last.

> [!TIP]
> **Try it — one owner, correct order**
>
> ```sh
> kubectl -n conflict-demo delete virtualservice notification-extra
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: notification
>   namespace: conflict-demo
> spec:
>   hosts:
>     - notification-service
>   http:
>     - match:
>         - headers:
>             testing:
>               exact: "true"
>       route:
>         - destination:
>             host: notification-service
>             subset: v2
>     - route:
>         - destination:
>             host: notification-service
>             subset: v1
> EOF
> ```
>
> Expect something like:
>
> ```text
> virtualservice.networking.istio.io "notification-extra" deleted
> virtualservice.networking.istio.io/notification configured
> ```
>
> Neither change restarted a pod. A `VirtualService` edit becomes an RDS push over the existing xDS stream, and the proxy swaps its route table in place — which is why the next checkpoint can run immediately rather than after a rollout.

## Verifying both paths, with enough requests to mean something

A routing change has at least two outcomes to check, and a fix that repairs one while breaking the other is a common way to lose marks on an exam and traffic in production. The header path and the default path are different rules; test both.

Volume matters too. With two subsets behind one Service, a single `200` can be luck — if routing were still splitting traffic, one request would show you one of the two answers and tell you nothing. Ten requests collapsed with `sort -u` turns "it worked once" into "every request went the same way".

> [!TIP]
> **Try it — both paths, ten requests each**
>
> ```sh
> kubectl -n conflict-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 10); do curl -s -X POST -H "testing: true" http://notification-service/notify; echo; done' | sort -u
> kubectl -n conflict-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
> ```
>
> Expect something like:
>
> ```text
> ["EMAIL","SMS"]
> ["EMAIL"]
> ```
>
> One line per path. Two lines from a single path would mean traffic is still being split somewhere — which is the failure mode a single request cannot detect, and the reason this checkpoint sends ten.

## Closing the loop on the evidence

Finish by re-checking the two sources that were wrong at the start. This is not ceremony: behaviour proves the outcome, the route table proves the mechanism, and the analyzer proves no second claimant crept back.

> [!TIP]
> **Try it — the evidence that was missing before**
>
> ```sh
> istioctl analyze -n conflict-demo
> istioctl proxy-config routes deploy/tester -n conflict-demo \
>   --name 80 -o json | grep -E '"cluster"|"exact_match"' | head
> ```
>
> Expect something like:
>
> ```text
> ✔ No validation issues found when analyzing namespace: conflict-demo.
>                "exact_match": "true",
>         "cluster": "outbound|80|v2|notification-service.conflict-demo.svc.cluster.local",
>         "cluster": "outbound|80|v1|notification-service.conflict-demo.svc.cluster.local",
> ```
>
> Both subsets now appear, in the order you wrote, with the header match attached to `v2` and the unconditional route last. The proxy's table and your YAML finally describe the same system — and `IST0109` is gone, confirming single ownership.

## The general method

This module's procedure generalises to any "the rule is right and the traffic is wrong" report:

```text
  1. Reproduce, and note whether the failure is PARTIAL or TOTAL
        partial → the match is wrong        total → the rule is never reached
  2. Check host ownership:   get virtualservice -o custom-columns=...HOSTS,GATEWAYS
  3. Read the proxy's table: proxy-config routes --name <port> -o json
  4. Compare with the YAML.  Disagreement means another object contributed.
  5. Fix one cause, re-verify BOTH paths with enough requests to be evidence.
```

Steps 2 and 3 take about ten seconds together and eliminate the two causes in this module outright.

> [!WARNING]
> **Pitfalls in reading and fixing**
>
> - **Trusting the YAML over the route table.** The file in your editor is an input to a merge, not a description of the outcome.
> - **Reading the tabular route output for a match problem.** Every rule shows `/*`. Use `-o json` when you need header, method or path conditions.
> - **Querying the wrong proxy.** The route table is per-proxy. Ask the **client** — the workload making the request — not the destination.
> - **Verifying one path.** Check the matched path *and* the default path after every routing change.
> - **Sending a single request as proof.** With two subsets behind one Service, one response proves nothing. Send ten and collapse the output.
> - **Waiting for a rollout after a routing change.** There is nothing to restart; if the table has not changed after a few seconds, the problem is delivery, and `istioctl proxy-status` ([section 030](../../section-030/module-02/course.md)) is the next command.

> *When the route table and the YAML disagree, believe the route table — it is the only account of what the merge produced.*

## Reference

- `istioctl proxy-config routes --help` — `--name`, `--output`, and the pod / `deploy/` target forms.
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — the whole `proxy-config` family, with worked output for each subcommand.
- [Envoy config dump](https://www.envoyproxy.io/docs/envoy/latest/operations/admin#get--config_dump) — the raw structure the command filters, useful when you want a field `istioctl` does not surface.
- [Virtual service reference](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — for re-checking match semantics while rewriting a rule order.
