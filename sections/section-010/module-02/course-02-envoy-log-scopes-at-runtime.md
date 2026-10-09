# Making A Proxy Narrate One Decision

Astronaut, `istioctl x describe pod` (the ship's dossier) tells you *which* policy judges your requests. Sometimes that is enough. When it is not, for example a policy with several rules, or a denial you are sure should not have happened, you need the communications officer to explain out loud how they decided. Envoy can do that on a running pod, without a restart. This part shows how.

## The administration interface

Every Envoy proxy carries a small web server for operators, separate from the ports it carries traffic on. In a sidecar it listens on **localhost:15000** inside the pod. So you can reach it from inside the container, and from nowhere else on the network.

That port is the machinery behind several commands you already use:

| Command | What it calls on the administration port |
| --- | --- |
| `istioctl proxy-config <sub> <pod>` | `GET localhost:15000/config_dump` |
| `istioctl proxy-config log <pod>` | `POST localhost:15000/logging?<scope>=<level>` |
| `pilot-agent request GET stats/prometheus` | `GET localhost:15000/stats/prometheus` |

`pilot-agent` is the small Istio program that looks after Envoy inside the sidecar container. `pilot-agent request` is a helper that talks to the administration port from inside the pod. Knowing this pairing helps twice. It explains why these commands need no extra credentials (they stay inside the pod), and it gives you a fallback when `istioctl` is not available.

One more fact matters: this is a **runtime** interface. Anything you change through it lives in the running process, not in configuration. It works at once, it is not recorded anywhere, and it is lost the moment the pod restarts. That is exactly right for a diagnostic switch, and exactly wrong as a way to configure anything.

## Scopes: Envoy's logging is not one dial

Envoy splits its own logging into **scopes**, one per subsystem, each with its own level. Think of it as asking one specific member of the communications team to think out loud, while the rest stay quiet. There are several dozen scopes; these are the ones worth knowing:

| Scope | Logs about |
| --- | --- |
| `rbac` | authorization decisions: which policy matched, and the verdict |
| `router` | route selection for a request |
| `connection` | the life of a TCP connection |
| `conn_handler` | listeners accepting connections |
| `upstream` | choosing an endpoint, and upstream health |
| `config` | xDS configuration being received and applied |
| `filter` | the filter chain a request passes through |

The levels are the usual ladder: `trace`, `debug`, `info` (the default), `warning`, `error`, `critical`, `off`.

Raising **one** scope gives you the decisions you care about at a volume you can read. Raising everything with a bare `--level debug` produces a flood. The line you need becomes harder to find than it was at `info`, and a busy proxy spends real processor time writing it all. Naming the scope is not politeness; it is the difference between a usable log and an unusable one.

## Watching an authorization decision

The `notification-post-only` `AuthorizationPolicy` on `describe-demo` is an `ALLOW` policy that lists only `POST`. An `ALLOW` policy forbids everything it does not name, so a `GET` gets a `403`. Now make the proxy explain that verdict in its own words.

### See the decision in the proxy's own words

Authorization is enforced by the receiving ship, so the scope must be raised on the `notification-service` pod. If you opened a new shell, set the pod name first.

<!-- astrona:playground:renew -->

```sh
export POD=$(kubectl -n describe-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
```

Raise the `rbac` scope, send a `GET`, and read the proxy's recent log lines:

```sh
istioctl proxy-config log $POD -n describe-demo --level rbac:debug
kubectl -n describe-demo exec deploy/tester -- \
  curl -s -o /dev/null -X GET http://notification-service/notify
kubectl -n describe-demo logs $POD -c istio-proxy --tail=30 | grep -i rbac
```

You should see something like:

```text
[... debug envoy rbac] checking request: requestedServerName: outbound_.80_._.notification-service.describe-demo.svc.cluster.local, sourceIP: 10.244.0.9:49182, ...
[... debug envoy rbac] enforced denied, matched policy none
```

The exact IP addresses, timestamps and pod name vary. `enforced denied, matched policy none` is the whole answer. *Enforced* means this was a real decision, not a dry run. *Denied* is the verdict. *Matched policy none* means the request reached an `ALLOW` policy, matched none of its rules, and was refused for that reason.

Two details in that output are worth knowing. `requestedServerName` is the Server Name Indication (SNI) value the connection carried: the address written on the outside of the sealed envelope. It tells the receiving proxy which service it is being addressed as, which helps later when a mutual TLS or gateway problem makes it the wrong value. And when a rule *does* match, the same log prints the policy name in the `ns[...]-policy[...]-rule[N]` form that `describe` shows under `RBAC policies`. That is how you tie a live decision back to a YAML file.

## Dry-run rules, and why "enforced" is in that line

Istio supports a dry-run mode. An `AuthorizationPolicy` with the annotation `istio.io/dry-run: "true"` is checked but never enforced. Its decisions appear in the `rbac` log and in metrics marked as *shadow* instead of *enforced*, and the request goes through anyway.

That is the intended way to introduce a strict policy on live traffic. Apply it in dry-run, watch the `rbac` log for requests it *would* have denied, fix the ones that turn out to be legitimate, then remove the annotation. The word `enforced` in the log line tells you at a glance which mode you were looking at.

## Putting the level back

A raised level costs processor time and log volume for as long as it is set, and nothing reminds you. On a shared cluster, a proxy someone left at `debug` is a cost that outlives the incident that justified it.

Run the command with no `--level` and it *reports* the current levels instead of setting them. That is also how you check a proxy somebody else was debugging last week.

### Restore the level and confirm it

Set `rbac` back to `info`, then list the levels:

```sh
istioctl proxy-config log $POD -n describe-demo --level rbac:info
istioctl proxy-config log $POD -n describe-demo | grep -E '^(rbac|router|upstream):'
```

You should see something like:

```text
rbac: info
router: info
upstream: info
```

Everything is back at the default. If your `istioctl` prints the scopes indented under an `active loggers:` heading, the `^` in the `grep` matches nothing; drop it and look for the three lines.

A pod restart would have done the same, because this is runtime state. But restarting a pod to undo a diagnostic is a heavier action than the diagnostic was, and on a workload with one replica it is an outage.

> [!TIP]
> Make putting the level back part of the same step as raising it. Before you close the terminal, run `istioctl proxy-config log` with no `--level` and check that every scope you touched reads `info`.

## Where a log level sits among the tools

A log scope is the narrowest instrument you have, and that is its value. Compare it with the other tools:

| Tool | What it looks at | The question it answers |
| --- | --- | --- |
| `istioctl analyze` | the whole configuration set | "Is this coherent?" |
| `istioctl x describe pod` | one workload's effective configuration | "What applies here?" |
| a log scope | one subsystem, one proxy, live | "Why did it decide that?" |
| `istioctl bug-report` | everything, frozen | "Someone else will look" |

Reach for a scope when you have already narrowed the problem to one workload and one behaviour, and you need the reasoning, not the outcome. Reach for it earlier and you read a lot of correct decisions.

## Common pitfalls

> [!WARNING]
> - **Leaving a proxy at `debug`.** It costs processor time and floods the log pipeline, and the setting lasts until the pod restarts. Put it back in the same working session.
> - **Using a global `--level debug`.** The volume buries the decision you were looking for. Name the scope: `rbac:debug`, `router:debug`.
> - **Expecting the change to last.** It is runtime state on one pod. A restart, a rollout or a reschedule loses it, and a second replica never had it.
> - **Setting the level on the wrong end.** Authorization is enforced by the receiving proxy, so `rbac:debug` belongs on the **destination** pod. The client's proxy has nothing to say about a decision it did not make.
> - **Reading `shadow` denials as enforced ones.** A dry-run policy logs its verdicts without acting on them. The word in the line tells you which you are looking at.

> *The administration interface on localhost:15000 is runtime state: it works at once, nothing records it, and it is gone at the next restart.*

## Your mission: Widen A Policy Without Weakening The Mesh

You can now read what applies to one workload, make its proxy explain an authorization decision, and put the log level back. Now prove it in a graded mission: a monitoring team's `GET` requests are refused, and you must allow them without opening the workload to everything, without relaxing mutual TLS, and with a forgotten `debug` log scope put back.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-010-02
```

Then start the mission:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-02/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-010/module-02/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-016-lab-010-02
astrona start ats-016-playground-010-02
```
