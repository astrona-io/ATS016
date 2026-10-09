# The Route Table Is The Ground Truth

Astronaut, on this planet two flight plans (`VirtualService` objects) claim one beacon and are merged in an order nobody chose, and one of them blocks its own header rule with a catch-all above it. Reading YAML can no longer tell you what will happen to a signal. Only the proxy knows. This part asks it, reads the answer, applies the two-part fix, and checks the result the way every routing fix should be checked.

## Asking a proxy what it holds

`istioctl proxy-config routes <pod-or-deployment> -n <namespace>` reads the orders book on one ship. It fetches the **route configuration the named proxy is running right now**: Envoy's own structure, in Envoy's own order, after every merge `istiod` (mission control) made.

### What the command reads

Underneath, `istioctl` reads the proxy's configuration dump from Envoy's administration page on port `15000` inside the pod, and keeps only the routes. That has two results. The answer is what the proxy really holds, not what you asked for. And it is per proxy: two workloads can hold different tables for the same host.

The subcommands are named after Envoy's building blocks: `routes`, `cluster`, `endpoint`, `listener`, `secret` and `log`. A **listener** (the radio channel the officer listens on) accepts the connection, a **route** (the flight plan table) picks a **cluster** (a destination squadron), and a cluster resolves to **endpoints** (each ship's actual address). Here only the route step matters, because a header match happens there or nowhere.

`--name 80` picks the route configuration named after the port. Envoy names each route configuration after the port it serves.

<!-- astrona:playground:renew -->

### See what the proxy will really do

Ask the tester's proxy for its route configuration for port 80, and keep only the lines that name clusters and matches:

```sh
istioctl proxy-config routes deploy/tester -n conflict-demo \
  --name 80 -o json | grep -E '"name"|"cluster"|"exact_match"|"prefix"' | head -20
```

You should see something like:

```text
  "name": "80",
        "cluster": "outbound|80|v1|notification-service.conflict-demo.svc.cluster.local",
        "cluster": "outbound|80|v1|notification-service.conflict-demo.svc.cluster.local",
```

Read the cluster names rather than counting lines. The `v1` subset appears twice, `v2` appears nowhere, and no header `exact_match` appears at all. That is the decisive evidence: as far as this proxy is concerned, the route to `v2` does not exist. JSON details differ between Istio versions; the cluster names are the stable part to read.

The table form (without `-o json`) is quicker, but it shows every rule's match as `/*`, which hides the very field you need here. Its `VIRTUAL SERVICE` column is still worth a look. It names the object that produced each route, and an empty value means Istio made a default route from the Service alone, which tells you your object is not being applied.

Whenever the proxy's table disagrees with the YAML in front of you, **the YAML is not the whole story**: some other object fed into what the proxy received. On this planet, that other object is `notification-extra`, the second claimant for the same host.

## The fix has two halves

The two causes need two changes. Doing them one at a time is what lets you tell which change fixed which symptom.

### Restore single ownership

Delete the duplicate claimant, so exactly one object describes the host. Until you do, any order you set can be reshuffled by the merge:

```sh
kubectl -n conflict-demo delete virtualservice notification-extra
```

You should see:

```text
virtualservice.networking.istio.io "notification-extra" deleted
```

### Order the surviving object's rules

Put the specific match first and the unconditional route last.

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

Neither change restarted a pod. `istiod` sent the new routes to the proxy as an RDS (Route Discovery Service) push over the connection it already had, the way mission control radios new orders to a ship in flight. The proxy swaps its route table in place, so you can check the result straight away.

## Check both paths, with enough requests to mean something

A routing change has at least two outcomes to check. The header path and the default path are different rules, and a fix that repairs one while breaking the other is a common way to lose points on an exam and traffic in production.

The number of requests matters too. With two subsets behind one Service, a single good answer can be luck. Ten requests, folded together with `sort -u`, turn "it worked once" into "every request went the same way".

### Send ten requests down each path

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

One line per path. Two lines from one path would mean traffic is still being split somewhere. A single request cannot show you that, which is why this check sends ten.

### Re-check the evidence that was wrong before

Finish by asking the two sources that were wrong at the start. Behaviour proves the outcome, the route table proves the mechanism, and the analyzer proves no second claimant came back:

```sh
istioctl analyze -n conflict-demo
istioctl proxy-config routes deploy/tester -n conflict-demo \
  --name 80 -o json | grep -E '"cluster"|"exact_match"' | head
```

You should see something like:

```text
✔ No validation issues found when analyzing namespace: conflict-demo.
               "exact_match": "true",
        "cluster": "outbound|80|v2|notification-service.conflict-demo.svc.cluster.local",
        "cluster": "outbound|80|v1|notification-service.conflict-demo.svc.cluster.local",
```

Both subsets now appear, in the order you wrote, with the header match attached to `v2` and the unconditional route last. The proxy's table and your YAML finally describe the same system, and the `IST0109` warning is gone, which confirms a single owner.

## The general method

This procedure works for any "the rule is right and the traffic is wrong" report:

1. **Reproduce it,** and note whether the failure is partial or total. Partial means the match is wrong. Total means the rule is never reached.
2. **Check host ownership:** `kubectl get virtualservice -o custom-columns=...` with the `HOSTS` and `GATEWAYS` columns.
3. **Read the proxy's table:** `istioctl proxy-config routes <client> --name <port> -o json`.
4. **Compare it with the YAML.** Disagreement means another object fed into it.
5. **Fix one cause,** then check both paths again with enough requests to count as evidence.

Steps 2 and 3 take about ten seconds together, and they rule out both causes in this module.

> [!TIP]
> Always ask the proxy of the **client**, the ship that sends the signal. It is the one that makes the routing decision.

## Common pitfalls

> [!WARNING]
> - **Trusting the YAML over the route table.** The file in your editor is an input to a merge, not a description of the result.
> - **Reading the table output for a match problem.** Every rule shows `/*`. Use `-o json` when you need header, method or path conditions.
> - **Asking the wrong proxy.** The route table is per proxy. Ask the client that sends the request, not the destination.
> - **Checking one path.** Check the matched path *and* the default path after every routing change.
> - **Sending a single request as proof.** With two subsets behind one Service, one answer proves nothing. Send ten and fold the output.
> - **Waiting for a rollout after a routing change.** There is nothing to restart. If the table has not changed after a few seconds, the problem is delivery from `istiod`, and `istioctl proxy-status` (mission control's roll call) is the next command.

> *When the route table and the YAML disagree, believe the route table: it is the only record of what the merge produced.*

## Your mission: Make The Header Route Actually Fire

You can now find a second claimant for a host, spot a shadowed rule, and prove a fix from the proxy and from real traffic. The mission gives you a planet where the header route never fires, for two separate reasons, and asks you to repair it so every request lands on the right version.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-020-01
```

Then start the mission:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-020/module-01/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-020/module-01/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-016-lab-020-01
astrona start ats-016-playground-020-01
```
