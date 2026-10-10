# The Route Table Is The Ground Truth

In the `conflict-demo` namespace, two `VirtualService` objects claim one host, and the proxy uses only one of them. One of them also shadows its own header rule with a catch-all above it. Reading YAML can no longer tell you what will happen to a request; only the proxy knows. This part asks the proxy, reads its answer, applies the two-part fix, and checks the result the way every routing fix should be checked.

## Asking a proxy what it holds

`istioctl proxy-config routes <pod-or-deployment> -n <namespace>` fetches the **route configuration that the named proxy is running right now**. That is Envoy's own structure, in Envoy's own order, after `istiod` has decided which objects to use. Underneath, `istioctl` reads the configuration dump from Envoy's administration interface on port `15000` inside the pod and keeps only the routes. So the answer is what the proxy really holds, not what you asked for. It is also per proxy: two workloads can hold different tables for the same host.

The subcommands are named after Envoy's building blocks: `routes`, `cluster`, `endpoint`, `listener`, `secret` and `log`. A **listener** accepts the connection on a port. A **route** picks a **cluster**, which is Envoy's name for a group of upstream pods, such as one subset of a Service. A cluster resolves to **endpoints**, the IP addresses and ports of those pods. Here only the route step matters, because a header match happens there or nowhere. The flag `--name 80` picks the route configuration that serves port `80`.

<!-- astrona:playground:renew -->

Ask the proxy of the `tester` pod for its route configuration for port `80`. The `grep` keeps only two kinds of lines: the clusters of a subset (`outbound|80|v...`) and the value of an `exact` header match:

```sh
istioctl proxy-config routes deploy/tester -n conflict-demo --name 80 -o json \
  | grep -E '"exact"|"cluster": "outbound\|80\|v'
```

You should see something like:

```text
                            "cluster": "outbound|80|v1|notification-service.conflict-demo.svc.cluster.local",
```

Only the `v1` subset appears. `v2` appears nowhere, and there is no `exact` header match at all. That is the decisive evidence: as far as this proxy is concerned, the route to `v2` does not exist. It also shows which object the proxy uses. The `notification` object has a header rule for `v2`, even if it is shadowed, so the one route here must come from `notification-extra`. In the JSON, a header match sits under `match.headers[].stringMatch.exact`; the field names differ between Istio versions, so the cluster names are the stable part to read.

The table form (without `-o json`) is quicker, but it shows the match of every rule as `/*`, which hides the very field you need here. Its `VIRTUAL SERVICE` column is still worth a look. It names the object that produced each route. An empty value means Istio built a default route from the Service alone, which tells you no `VirtualService` is in use for that host.

Whenever the proxy's table disagrees with the YAML in front of you, **the YAML is not the whole story**. Some other object, or the order of the rules, decided what the proxy received. In this namespace, both are true.

## The fix has two halves

The two causes need two changes. Making them one at a time lets you tell which change fixed which symptom. First, restore single ownership by deleting the duplicate object, so exactly one `VirtualService` describes the host:

```sh
kubectl -n conflict-demo delete virtualservice notification-extra
```

You should see:

```text
virtualservice.networking.istio.io "notification-extra" deleted from conflict-demo namespace
```

Now only `notification` describes the host, so `istiod` uses its rules. Its catch-all still sits above the header rule, though, so header requests still reach `v1`. The second change puts the specific match first and the unconditional route last.

Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: conflict-demo
spec:
  hosts:
    - notification-service
  http:
    - match:
        - headers:
            testing:
              exact: "true"
      route:
        - destination:
            host: notification-service
            subset: v2
    - route:
        - destination:
            host: notification-service
            subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

You should see:

```text
virtualservice.networking.istio.io/notification configured
```

Neither change restarted a pod. `istiod` sent the new routes to the proxy as an RDS (Route Discovery Service) update, the part of xDS that carries route configuration, over the connection it already had. The proxy swaps its route table in place, so you can check the result straight away.

## Check both paths, with enough requests

A routing change has at least two outcomes to check. The header path and the default path are different rules, and a fix that repairs one while it breaks the other is a common way to lose points on an exam and traffic in production. The number of requests matters too. With two subsets behind one Service, a single good answer can be luck. Ten requests, folded together with `sort -u`, turn "it worked once" into "every request went the same way".

Send ten requests with the header and ten without:

```sh
kubectl -n conflict-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST -H "testing: true" http://notification-service/notify; echo; done' | sort -u
kubectl -n conflict-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
```

You should see something like:

```text
["EMAIL","SMS"]
["EMAIL"]
```

There is one line per path. Two lines from one path mean traffic is still being split somewhere, which a single request cannot show. Right after an apply, the proxy can take a few seconds to receive the new routes, so if a path shows two lines, wait a moment and run the loop again. Finish by asking the two sources that were wrong at the start. The requests prove the outcome, the route table proves the mechanism, and the analyzer proves no second owner came back:

```sh
istioctl analyze -n conflict-demo
istioctl proxy-config routes deploy/tester -n conflict-demo --name 80 -o json \
  | grep -E '"exact"|"cluster": "outbound\|80\|v'
```

You should see something like:

```text
✔ No validation issues found when analyzing namespace: conflict-demo.
                                        "exact": "true"
                            "cluster": "outbound|80|v2|notification-service.conflict-demo.svc.cluster.local",
                            "cluster": "outbound|80|v1|notification-service.conflict-demo.svc.cluster.local",
```

Both subsets now appear in the order you wrote, with the header match attached to `v2` and the unconditional route last. The proxy's table and your YAML describe the same system, and the `IST0109` message is gone, which confirms a single owner.

## The general method

The same procedure works for any "the rule is right and the traffic is wrong" report:

1. **Reproduce it,** and note whether the failure is partial or total. Partial means the match is wrong. Total means the rule is never reached.
2. **Check host ownership** with `kubectl get virtualservice -o custom-columns=...` and the `HOSTS` and `GATEWAYS` columns.
3. **Read the proxy's table** with `istioctl proxy-config routes <client> --name <port> -o json`.
4. **Compare it with the YAML.** A difference means another object or the rule order decided the result.
5. **Fix one cause,** then check both paths again with enough requests to count as evidence.

Steps 2 and 3 take about ten seconds together, and they rule out both causes in this module.

> [!TIP]
> Always ask the proxy of the **client**, the pod that sends the request. Its proxy makes the routing decision.

You can now read what a proxy really holds with `istioctl proxy-config routes`, find a second owner and a shadowed rule, fix them one at a time, and prove the fix on both paths. A clean route table assumes `istiod` delivered the configuration in the first place. If the table does not change a few seconds after a fix, the problem is delivery, and `istioctl proxy-status` is the command that checks it.

## Common pitfalls

> [!WARNING]
> - **Trusting the YAML over the route table.** The file in your editor is one input. The route table is the result.
> - **Reading the table output for a match problem.** Every rule shows `/*`. Use `-o json` when you need header, method or path conditions.
> - **Asking the wrong proxy.** The route table is per proxy. Ask the client that sends the request, not the destination.
> - **Checking one path.** Check the matched path *and* the default path after every routing change.
> - **Sending a single request as proof.** With two subsets behind one Service, one answer proves nothing. Send ten and fold the output.
> - **Waiting for a rollout after a routing change.** There is nothing to restart. If the table has not changed after a few seconds, check delivery with `istioctl proxy-status`.

## Your mission: Make The Header Route Actually Fire

You can now find a second owner for a host, spot a shadowed rule, and prove a fix from the proxy and from real requests. The graded lab gives you a namespace where the header route never fires, for two separate reasons, and asks you to repair it so every request reaches the right version.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-020-01
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-020/module-01/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-020/module-01/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-020-01
astrona start ats-016-playground-020-01
```
