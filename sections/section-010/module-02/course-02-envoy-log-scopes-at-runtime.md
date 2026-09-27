# Part 2 — Making A Proxy Narrate One Decision

> Prerequisite: [Part 1 — What describe Resolves For One Workload](./course-01-what-describe-resolves.md). Next: [Part 3 — Capturing A Cluster With bug-report](./course-03-bug-report-and-handover.md).

`describe` told you *which* policy judges your requests. Sometimes that is enough. When it is not — a policy with several rules, a denial you are sure should not have happened, a routing decision you cannot reproduce — you need the proxy to say out loud how it decided. Envoy can do that, on a running pod, without a restart, and this part is the mechanism behind that.

## The admin interface

Every Envoy carries a small HTTP server for operators, separate from the ports it proxies traffic on. In a sidecar it listens on **localhost:15000** inside the pod, which means it is reachable from inside the container and from nowhere else on the network.

That port is the machinery behind several commands you already use:

```text
  istioctl proxy-config <sub> <pod>   ──▶  GET  localhost:15000/config_dump
  istioctl proxy-config log <pod>     ──▶  POST localhost:15000/logging?<scope>=<level>
  pilot-agent request GET stats/prometheus ─▶ GET localhost:15000/stats/prometheus
```

`pilot-agent` is the small Istio process that supervises Envoy inside the sidecar container; `pilot-agent request` is a convenience wrapper that talks to that admin port from inside the pod. Knowing the pairing is useful twice: it explains why these commands need no extra credentials (they are local to the pod), and it gives you a fallback when `istioctl` is unavailable.

The other structural fact: this is a **runtime** interface. Anything you change through it is held in the running process, not in configuration. It takes effect immediately, it is not recorded anywhere, and it is lost the moment the pod restarts. That is exactly right for a diagnostic switch and exactly wrong as a way to configure anything.

## Scopes: Envoy's logging is not one dial

Envoy splits its own logging into **scopes**, one per subsystem, each with an independent level. There are several dozen; these are the ones worth knowing:

| Scope | Logs about |
| --- | --- |
| `rbac` | authorization decisions — which policy matched, and the verdict |
| `router` | route selection for a request |
| `connection` | TCP connection lifecycle |
| `conn_handler` | listeners accepting connections |
| `upstream` | endpoint selection and upstream health |
| `config` | xDS configuration being received and applied |
| `filter` | the filter chain a request passes through |

The levels are the usual ladder: `trace`, `debug`, `info` (the default), `warning`, `error`, `critical`, `off`.

Raising **one** scope gives you the decisions you care about at a volume you can read. Raising everything with a bare `--level debug` produces a flood in which the line you need is genuinely harder to find than it was at `info`, and costs measurable CPU on a busy proxy. Scoped is not a politeness convention; it is the difference between a usable log and an unusable one.

## Watching an authorization decision

Part 1 established that the `ALLOW` policy denies any request it does not explicitly permit, and that a `GET` therefore gets a `403`. Now make the proxy explain that verdict in its own terms.

> [!TIP]
> **Try it — the decision in the proxy's own words**
>
> ```sh
> istioctl proxy-config log $POD -n describe-demo --level rbac:debug
> kubectl -n describe-demo exec deploy/tester -- \
>   curl -s -o /dev/null -X GET http://notification-service/notify
> kubectl -n describe-demo logs $POD -c istio-proxy --tail=30 | grep -i rbac
> ```
>
> Expect something like:
>
> ```text
> [... debug envoy rbac] checking request: requestedServerName: outbound_.80_._.notification-service.describe-demo.svc.cluster.local, sourceIP: 10.244.0.9:49182, ...
> [... debug envoy rbac] enforced denied, matched policy none
> ```
>
> `enforced denied, matched policy none` is the whole answer, and it is worth parsing word by word: *enforced* means this was a real decision rather than a dry run, *denied* is the verdict, and *matched policy none* is the implicit-deny clause from Part 1 firing — the request reached an `ALLOW` policy, matched none of its rules, and was refused on that basis. The exact IPs, timestamps and pod name vary.

Two details in that output repay attention. `requestedServerName` is the SNI value the connection carried, which is how the destination proxy knows which service it is being addressed as — useful later when an mTLS or gateway problem makes it the wrong value. And when a rule *does* match, the same log prints the policy identifier in the `ns[...]-policy[...]-rule[N]` form that `describe` showed you in Part 1, which is how you tie a live decision back to a YAML file.

## Shadow rules, and why "enforced" is a word in that line

Istio supports a dry-run mode: an `AuthorizationPolicy` annotated `istio.io/dry-run: "true"` is evaluated but never enforced. Its decisions appear in the `rbac` log and in metrics with a *shadow* denotation rather than an *enforced* one, and the request proceeds regardless.

That is the intended way to introduce a restrictive policy on live traffic: apply it in dry-run, watch the `rbac` log for requests it *would* have denied, fix the ones that turn out to be legitimate, then remove the annotation. The word `enforced` in the line above is how you tell, at a glance, which mode you were looking at.

## Putting the level back

A raised level costs CPU and log volume for as long as it is set, and nothing will remind you. On a shared cluster, a proxy someone left at `debug` is a cost that outlives the incident that justified it.

Run with no `--level` and the same command *reports* the current levels instead of setting them — which is also how you audit a proxy somebody else was debugging last week.

> [!TIP]
> **Try it — restoring the level and confirming it**
>
> ```sh
> istioctl proxy-config log $POD -n describe-demo --level rbac:info
> istioctl proxy-config log $POD -n describe-demo | grep -E '^(rbac|router|upstream):'
> ```
>
> Expect something like:
>
> ```text
> rbac: info
> router: info
> upstream: info
> ```
>
> Everything back at the default. Because this is runtime state, a pod restart would have done the same thing — but restarting a pod to undo a diagnostic is a heavier action than the diagnostic was, and on a single-replica workload it is an outage.

## Where a log level sits among the tools

It is the narrowest instrument in this course, and that is its value:

```text
  analyze        the whole configuration set        "is this coherent?"
  describe       one workload's effective config    "what applies here?"
  log scope      one subsystem, one proxy, live     "why did it decide that?"
  bug-report     everything, frozen                 "someone else will look"
```

Reach for a scope when you have already narrowed the problem to one workload and one behaviour, and you need the reasoning rather than the outcome. Reaching for it earlier means reading a lot of correct decisions.

> [!WARNING]
> **Pitfalls with runtime log levels**
>
> - **Leaving a proxy at `debug`.** It costs CPU and floods the log pipeline, and the setting survives until the pod restarts. Restore it in the same working session.
> - **Using a global `--level debug`.** The volume buries the decision you were looking for. Name the scope: `rbac:debug`, `router:debug`.
> - **Expecting the change to persist.** It is runtime state on one pod. A restart, a rollout, or a rescheduling loses it — and a second replica never had it.
> - **Setting the level on the wrong end.** Authorization is enforced inbound, so `rbac:debug` belongs on the **destination** pod. The client's proxy has nothing to say about a decision it did not make.
> - **Reading `shadow` denials as enforced ones.** A dry-run policy logs its verdicts without acting on them; the word in the line tells you which you are looking at.

> *The admin interface on localhost:15000 is runtime state: immediate, unrecorded, and gone at the next restart.*

## Reference

- [Change Envoy message logging levels](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/#change-envoy-message-logging-levels) — the scope syntax and the full list of scope names.
- `istioctl proxy-config log --help` — including `--reset`, and the `<scope>:<level>` comma-separated form for setting several at once.
- [Envoy administration interface](https://www.envoyproxy.io/docs/envoy/latest/operations/admin) — every endpoint on port 15000, not just logging; the reference behind `pilot-agent request`.
- [Dry-run authorization policies](https://istio.io/latest/docs/tasks/security/authorization/authz-dry-run/) — the annotation, and how to read shadow decisions in logs and metrics.
