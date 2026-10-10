# Making A Proxy Narrate One Decision

`istioctl x describe pod` tells you which policy applies to requests for a workload. Sometimes that is enough. When it is not, for example with a policy that has several rules, or a denial you are sure should not happen, you need the sidecar proxy to write down how it decided. Envoy can do that on a running pod, without a restart. This part shows how to switch that on for one subsystem, read the result, and switch it off again.

## The administration interface

Every Envoy proxy runs a small web server for operators, separate from the ports that carry traffic. In a sidecar it listens on **localhost:15000** inside the pod, so you can reach it from inside the pod and from nowhere else on the network. That port is behind several commands you already use:

| Command | What it calls on the administration port |
| --- | --- |
| `istioctl proxy-config <type> <pod>` | `GET localhost:15000/config_dump` |
| `istioctl proxy-config log <pod>` | `POST localhost:15000/logging?<scope>=<level>` |
| `pilot-agent request GET stats/prometheus` | `GET localhost:15000/stats/prometheus` |

`pilot-agent` is the Istio program that starts and manages Envoy inside the `istio-proxy` container, and `pilot-agent request` sends a request to the administration port from inside the pod. Knowing this pairing helps twice. It explains why these commands need no extra credentials, because they stay inside the pod. It also gives you a fallback when `istioctl` is not available.

One more fact matters: this is a **runtime** interface. A change made through it lives only in the running Envoy process, not in any Kubernetes object. It takes effect at once, nothing records it, and it is lost when the pod restarts. That is right for a diagnostic switch and wrong as a way to configure anything.

## Scopes: Envoy's logging is not one setting

Envoy splits its own logging into **scopes**, one per subsystem, and each scope has its own level. There are several dozen scopes. These are the ones worth knowing:

| Scope | Logs about |
| --- | --- |
| `rbac` | authorization decisions: which policy matched, and the result |
| `router` | route selection for a request |
| `connection` | the life of a TCP connection |
| `conn_handler` | listeners accepting connections |
| `upstream` | choosing an endpoint, and upstream health |
| `config` | xDS configuration being received and applied |
| `filter` | the filter chain a request passes through |

The levels, from most to least output, are `trace`, `debug`, `info`, `warning`, `error`, `critical` and `off`. In a default Istio 1.30 install, every sidecar starts with all scopes at `warning`, except `misc`, which is at `error`.

Raising **one** scope gives you the decisions you care about at a volume you can read. Raising every scope with a bare `--level debug` produces a flood. The line you need becomes harder to find, and a busy proxy spends real processor time writing it all. So always name the scope.

## Watching an authorization decision

The `notification-post-only` `AuthorizationPolicy` in `describe-demo` is an `ALLOW` policy that lists only `POST`. An `ALLOW` policy denies everything it does not name, so a `GET` gets `403`. Now make the proxy explain that result in its own words. Authorization is enforced by the receiving proxy, so you raise the scope on the `notification-service` pod. If you opened a new shell, store the pod name first.

<!-- astrona:playground:renew -->

```sh
export POD=$(kubectl -n describe-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
```

Raise the `rbac` scope to `debug`, send a `GET` from the `tester` pod, and read the recent log lines of the `istio-proxy` container:

```sh
istioctl proxy-config log $POD -n describe-demo --level rbac:debug
kubectl -n describe-demo exec deploy/tester -- \
  curl -s -o /dev/null -X GET http://notification-service/notify
sleep 2
kubectl -n describe-demo logs $POD -c istio-proxy --tail=30 | grep -i rbac
```

You should see something like this (shortened: the first command prints the level of every scope, and long lines are cut):

```text
notification-service-v1-54dd46d4b6-7cfkk.describe-demo:
active loggers:
  rbac: debug
[2026-10-09T22:49:10.613Z] "GET /notify HTTP/1.1" 403 - rbac_access_denied_matched_policy[none] - "-" 0 19 0 - "-" "curl/8.22.0" ...
2026-10-09T22:49:11.332052Z	debug	envoy rbac external/envoy/source/extensions/filters/http/rbac/rbac_filter.cc:266	checking request: requestedServerName: outbound_.80_.v1_.notification-service.describe-demo.svc.cluster.local, sourceIP: 10.244.0.9:59898, ...
2026-10-09T22:49:11.332250Z	debug	envoy rbac external/envoy/source/extensions/filters/http/rbac/rbac_filter.cc:233	enforced denied, matched policy none	thread=29
```

The IP addresses, timestamps and pod name differ on your cluster. Setting a level prints the new level of every scope, and `rbac` now shows `debug`. The `grep` also keeps the access log line for the `GET`, because its details field, `rbac_access_denied_matched_policy[none]`, contains `rbac`. The two `debug` lines below it come from the `rbac` scope you raised. The `sleep 2` is there because the proxy writes its log in short batches; if the lines still do not appear, read the log again. `enforced denied, matched policy none` is the whole answer. *Enforced* means this was a real decision, not a dry run. *Denied* is the result. *Matched policy none* means an `ALLOW` policy selects this workload, the request matched none of its rules, and so the proxy refused it.

Two details in that output are worth knowing. `requestedServerName` is the Server Name Indication (SNI) value of the connection: the name the client proxy put in the TLS handshake to say which service it wants. It becomes important later, when an mTLS or gateway problem makes it the wrong value. And when a rule *does* match, the same log prints the policy name in the `ns[...]-policy[...]-rule[N]` form that `describe` shows under `RBAC policies`.

## Dry-run policies, and why "enforced" is in that line

Istio supports a dry-run mode for authorization. An `AuthorizationPolicy` with the annotation `istio.io/dry-run: "true"` is evaluated but never enforced. Its results appear in the `rbac` log and in metrics marked as *shadow* instead of *enforced*, and the request goes through.

That is the intended way to introduce a strict policy on live traffic. Apply it in dry-run mode, watch the `rbac` log for requests it *would* deny, fix the ones that turn out to be legitimate, and then remove the annotation. The word `enforced` or `shadow` in the log line tells you at once which mode you are looking at.

## Putting the level back

A raised level costs processor time and log volume for as long as it is set, and nothing reminds you. On a shared cluster, a proxy someone left at `debug` is a cost that outlives the incident. Run the command with no `--level`, and it reports the current levels instead of setting them. That is also how you check a proxy somebody else was debugging last week.

Set `rbac` back to `warning`, the level almost every other scope uses, then list the levels:

```sh
istioctl proxy-config log $POD -n describe-demo --level rbac:warning
istioctl proxy-config log $POD -n describe-demo | grep -E '(rbac|router|upstream):'
```

You should see something like this (shortened: the list of every scope that the first command prints is left out):

```text
  rbac: warning
  router: warning
  upstream: warning
```

All three lines read `warning` again. A pod restart would have reset the level too, because it is runtime state. But restarting a pod to undo a diagnostic is heavier than the diagnostic was, and on a workload with one replica it is an outage.

> [!TIP]
> Make putting the level back part of the same step as raising it. Before you close the terminal, run `istioctl proxy-config log` with no `--level` and check every scope you touched.

## Where a log level sits among the tools

A log scope is the narrowest tool you have, and that is its value:

| Tool | What it looks at | The question it answers |
| --- | --- | --- |
| `istioctl analyze` | the whole configuration set | "Is this coherent?" |
| `istioctl x describe pod` | one workload's effective configuration | "What applies here?" |
| a log scope | one subsystem, one proxy, live | "Why did it decide that?" |
| `istioctl bug-report` | the control plane and selected proxies, frozen | "Someone else will look" |

Use a scope when you have already narrowed the problem to one workload and one behaviour, and you need the reasoning, not the outcome. Use it earlier and you read a lot of correct decisions.

You now know that the administration interface on `localhost:15000` lets you change a proxy's log level at runtime, that one named scope such as `rbac` gives a readable answer, and that the level must go back to `warning` afterwards. The receiving proxy's `rbac` log names the result of every authorization decision. Both `describe` and a log scope need you at the terminal while the problem happens. The question still open is what to do when it does not happen while you watch, or when someone else must investigate.

## Common pitfalls

> [!WARNING]
> - **Leaving a proxy at `debug`.** It costs processor time and floods the log pipeline, and the setting lasts until the pod restarts. Put it back in the same working session.
> - **Using a global `--level debug`.** The volume buries the decision you are looking for. Name the scope: `rbac:debug`, `router:debug`.
> - **Expecting the change to last.** It is runtime state on one pod. A restart, a rollout or a reschedule loses it, and a second replica never had it.
> - **Setting the level on the wrong end.** The receiving proxy enforces authorization, so `rbac:debug` belongs on the **destination** pod.
> - **Reading `shadow` denials as enforced ones.** A dry-run policy logs its results without acting on them.

## Your mission: Widen A Policy Without Weakening The Mesh

You can now read what applies to one workload, make its proxy explain an authorization decision, and put the log level back. The graded lab gives you a monitoring team whose `GET` requests are refused, and asks you to allow them without opening the workload to every method, without relaxing mTLS, and with a forgotten `debug` log scope put back.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-010-02
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-02/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-010/module-02/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-010-02
astrona start ats-016-playground-010-02
```
