# Accepted, Never Applied

This is the control plane failure with no outage at all, and so the hardest one to find. You apply a `VirtualService`, `kubectl apply` prints `created`, and the object is there. Nothing happens, because `istiod` never sends it to the proxies. This part shows how that happens, where the evidence is recorded, and the order in which to check the control plane.

## How a bad object gets stored

Normally the validating admission webhook `validation.istio.io` refuses an invalid Istio object while you apply it. With `istiod` running, a `VirtualService` whose weights add up to 120 is never stored. The webhook, however, is part of `istiod`, so there are two ways for a bad configuration to end up stored and unused.

The first way is a webhook that was skipped. The webhook has a `failurePolicy`, just like the injection webhook. Istio installs it as `Ignore`, and `istiod` changes it to `Fail` once it is ready. If `istiod` cannot be reached **and** the policy is `Ignore`, for example during the install or because someone changed it, the API server stores the object without a check. `kubectl apply` prints `created`, and nothing reports a problem. When `istiod` comes back, it reads the stored object, finds it invalid, and never sends it to the proxies. The object sits in etcd, the cluster's database, and does nothing.

The second way needs no outage at all. Some configuration looks valid to the webhook, but a **proxy** refuses it when it arrives. The proxy sends back a NACK, a negative acknowledgement, and keeps its previous configuration. `istiod` counts every NACK in `pilot_total_xds_rejects`. Either way, the proxies keep running their previous configuration, and your change never takes effect.

## Every ordinary tool shows nothing wrong

Once a bad object is stored, the usual Kubernetes tools all report it as normal. This is what makes the failure so slow to find:

| You run | It says | What is really true |
| --- | --- | --- |
| `kubectl get` | The object exists | It does |
| `kubectl describe` | No events, no conditions | Istio networking objects have no status field that reports a problem |
| A request | Behaves as if the object were absent | For the proxies, it is absent |
| `istioctl proxy-status -v 1` | `SYNCED`, or `ERROR` if a proxy rejected it | `ERROR` is the one hint, and only if a proxy refused it |

## Where the evidence is recorded

Three places record what really happened: the `istiod` log, the `istiod` metrics, and `istioctl analyze`, which reads every Istio object in a namespace together and reports the ones that cannot work. Checking them is the last step of every "I applied it and nothing happened" investigation.

<!-- astrona:playground:renew -->

Search the `istiod` log for rejections, and read the two error counters:

```sh
kubectl -n istio-system logs deploy/istiod --tail=200 | grep -i -E 'reject|invalid'
kubectl -n istio-system exec deploy/istiod -- \
  curl -s localhost:15014/metrics | grep -E 'pilot_total_xds_rejects|pilot_total_xds_internal_errors'
```

On a healthy playground both commands may print nothing. These counters are **missing** until they have gone up at least once, so any line at all is the signal, and its value matters less. Then run the analyzer on the namespace:

```sh
istioctl analyze -n cphealth-demo
```

On the healthy playground it reports no issues. When a stored object is invalid, the analyzer names it, with the code `IST0106` (`SchemaValidationError`) and the same reason the webhook would have given, such as `total destination weight 120 != 100`.

> [!TIP]
> Applying an object again with the same content does not retry a push. If a change "did nothing", look for the rejection instead of applying it again.

## The investigation order

Put the module together and you get a short checklist for any suspected control plane problem. Work it from top to bottom:

| Step | Check | Question it answers |
| --- | --- | --- |
| 1 | `kubectl -n istio-system get pods -l app=istiod` | Is it ready? How many restarts? How old? |
| 2 | `kubectl -n istio-system logs deploy/istiod` with `grep -iE 'reject\|error\|warn'` | What is it complaining about? |
| 3 | The metrics on port `15014`: pushes, rejects, errors | Is configuration reaching the proxies? |
| 4 | Make a small change, then repeat steps 1 to 3 | Does a change actually travel? |
| 5 | `istioctl proxy-status -v 1` | Did it reach every proxy? |

Step 4 is the one that tells a frozen mesh from a healthy one. Every earlier step can look fine on a control plane that is not doing its job.

You can now explain how an invalid object ends up stored and unused, and you know the three places that record it: the `istiod` log, the reject counter and `istioctl analyze`. With the investigation order, you can check a control plane from its pod status to the proxies. What this module did not answer is how to read the per-proxy state in `istioctl proxy-status` in detail.

## Common pitfalls

> [!WARNING]
> - **Trusting `kubectl apply` output when the validation webhook may have been skipped.** If the webhook could not run, an invalid object can exist and never be sent.
> - **Expecting `kubectl describe` to show a rejection.** Istio networking objects have no status conditions. The `istiod` log, `pilot_total_xds_rejects` and `istioctl analyze` are the evidence.
> - **Applying an object again because nothing happened.** The same content changes nothing and does not retry a push. Fix the rejection.
> - **Reading a missing counter as "cannot tell".** `pilot_total_xds_rejects` appears only after the first rejection. No line means zero.

## Your mission: The Mesh Works And Nothing Can Change

You can now tell a frozen control plane from a healthy one, bring `istiod` back, and find an object that was stored but never sent. The graded lab gives you a namespace where traffic flows, nothing can change, and one stored `VirtualService` will never be served, and asks you to restore the control plane and remove or correct that object.

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
