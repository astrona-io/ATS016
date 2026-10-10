# Stored Without Validation

This is the control plane failure with no outage at all, and so the hardest one to find. Someone applies a `VirtualService`, `kubectl apply` prints `created`, and the object is there. Then requests start to behave in a way nobody configured on purpose, because the object is invalid and nothing checked it. This part shows how that happens, where the evidence is recorded, and the order in which to check the control plane.

## How a bad object gets stored

Normally the validating admission webhook refuses an invalid Istio object while you apply it. With `istiod` running, an object the webhook refuses is never stored. The webhook, however, is part of `istiod`, so it only protects the cluster while `istiod` can answer.

The webhook has a `failurePolicy`, just like the injection webhook. Istio installs two validating webhook configurations: `istio-validator-istio-system`, with the webhook `rev.validation.istio.io`, and `istiod-default-validator`, with the webhook `validation.istio.io`. A running `istiod` sets both to `Fail`. If `istiod` cannot be reached **and** both policies are `Ignore`, for example during an install or because someone changed them, the API server stores the object without a check. `kubectl apply` prints `created`, and nothing reports a problem.

When `istiod` comes back, it does not check the stored object again. It translates the object as it is and sends the result to the proxies. In this module's lab, the stored object is a `VirtualService` with one HTTP rule that has both a `redirect` and a `route`. The webhook would have refused it, but once stored, the proxies get the redirect, and a `POST` to `notification-service` returns `301` with a redirect to `/v2` instead of `200`.

There is a second, separate case that needs no outage at all. Some configuration looks valid to the webhook, but a **proxy** refuses it when it arrives. The proxy sends back a NACK, a negative acknowledgement, and keeps its previous configuration. `istiod` counts every NACK in `pilot_total_xds_rejects`, and `istioctl proxy-status -v 1` shows `ERROR` for that proxy. In that case your change never takes effect on that proxy.

## Every ordinary tool shows nothing wrong

Once an invalid object is stored, the usual Kubernetes tools all report it as normal. This is what makes the failure so slow to find:

| You run | It says | What is really true |
| --- | --- | --- |
| `kubectl get` | The object exists | It does |
| `kubectl describe` | No events, no conditions | Istio networking objects have no status field that reports a problem |
| A request | An answer nobody expected, such as a `301` | The proxies serve the invalid object as it is |
| `istioctl proxy-status -v 1` | `SYNCED` | The proxies did accept it; `ERROR` appears only when a proxy refuses configuration |

## Where the evidence is recorded

Three places can record what happened: `istioctl analyze`, the `istiod` log and the `istiod` metrics. `istioctl analyze` reads every Istio object in a namespace together and reports the ones that cannot work. It is the one that names a stored invalid object; the log and the counters are the evidence for the second case, a proxy that refused configuration.

<!-- astrona:playground:renew -->

Search the `istiod` log for rejections, and read the two error counters:

```sh
kubectl -n istio-system logs deploy/istiod --tail=200 | grep -i -E 'reject|invalid'
kubectl -n istio-system exec deploy/istiod -- \
  curl -s localhost:15014/metrics | grep -E 'pilot_total_xds_rejects|pilot_total_xds_internal_errors'
```

On a healthy playground both commands may print nothing. These counters are **missing** until they have gone up at least once, so any line at all is the signal, and its value matters less. A stored invalid object leaves no trace here either: `istiod` does not log it, because it does not check it again. Then run the analyzer on the namespace:

```sh
istioctl analyze -n cphealth-demo
```

On the healthy playground it reports no issues. When a stored object is invalid, the analyzer names it with the code `IST0106` (`SchemaValidationError`) and the same reason the webhook would have given, for example `HTTP route cannot contain both route and redirect`.

> [!TIP]
> When a request behaves in a way no one configured, run `istioctl analyze` before you read any proxy configuration. An object that skipped validation shows up there as `IST0106`.

## The investigation order

Put the module together and you get a short checklist for any suspected control plane problem. Work it from top to bottom:

| Step | Check | Question it answers |
| --- | --- | --- |
| 1 | `kubectl -n istio-system get pods -l app=istiod` | Is it ready? How many restarts? How old? |
| 2 | `kubectl -n istio-system logs deploy/istiod` with `grep -iE 'reject\|error\|warn'` | What is it complaining about? |
| 3 | The metrics on port `15014`: pushes, rejects, errors | Is configuration reaching the proxies? |
| 4 | `istioctl analyze` | Is any stored object invalid? |
| 5 | Make a small change, then repeat steps 1 to 3 | Does a change actually travel? |
| 6 | `istioctl proxy-status -v 1` | Did it reach every proxy? |

Step 5 is the one that tells a frozen mesh from a healthy one. Every earlier step can look fine on a control plane that is not doing its job.

You can now explain how an invalid object ends up stored, why `istiod` serves it as it is once it is back, and why `istioctl analyze` is the tool that finds it. You also know the separate case of a proxy that refuses configuration, recorded by `pilot_total_xds_rejects` and `ERROR` in `istioctl proxy-status -v 1`. With the investigation order, you can check a control plane from its pod status to the proxies. What this module did not answer is how to read the per-proxy state in `istioctl proxy-status` in detail.

## Common pitfalls

> [!WARNING]
> - **Trusting `kubectl apply` output when the validation webhook may have been skipped.** If the webhook could not run, an invalid object can be stored and served as it is.
> - **Expecting `kubectl describe` or the `istiod` log to show a stored invalid object.** Istio networking objects have no status conditions, and `istiod` does not check the object again. `istioctl analyze` is the evidence.
> - **Relaxing only one validating webhook.** Istio installs two; while either one still enforces `Fail`, the API server refuses the object.
> - **Reading a missing counter as "cannot tell".** `pilot_total_xds_rejects` appears only after the first rejection. No line means zero.

## Your mission: The Mesh Works And Nothing Can Change

You can now tell a frozen control plane from a healthy one, bring `istiod` back, and find an object that was stored without validation. The graded lab gives you a namespace where `istiod` is down and one stored `VirtualService` skipped validation, and asks you to restore the control plane, find that object with the analyzer, and remove or correct it so requests return `200` again.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-030-01
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-01/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-030/module-01/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-030-01
astrona start ats-016-playground-030-01
```
