# Accepted, Never Applied

Astronaut, this is the control plane failure with no outage at all, and so the hardest one to find. You apply a `VirtualService` (a flight plan). `kubectl apply` prints `created`. The object is there. And nothing happens, because mission control (`istiod`) refused to send it to the ships. This part shows how that happens, where the evidence lives, and the order to check things in.

## How a bad object gets stored

Normally the validation webhook, the registry clerk, refuses an invalid Istio object while you apply it. With `istiod` running, a `VirtualService` whose weights add up to 120 never gets stored. But the clerk is part of `istiod`, so two situations can let a bad object through.

### Route one: the clerk was away

The validation webhook has a `failurePolicy`, just like the injection webhook. If `istiod` is not reachable **and** the policy lets the write go ahead, the Kubernetes API server stores the object without any check. `kubectl apply` prints `created`, and nothing anywhere reports a problem.

When `istiod` comes back, it reads the stored object, finds it invalid, and never sends it to the proxies. The object sits in the archive (etcd) and does nothing.

### Route two: the ship refused the orders

The same end state can happen with a perfectly healthy control plane. Some configuration looks valid to the webhook, but a **proxy** refuses it when it arrives. The proxy radios back a NACK: "orders rejected, keeping the old ones". `istiod` counts every NACK in `pilot_total_xds_rejects`.

Either way, the proxies keep running their previous orders, and your change never takes effect.

## Every ordinary tool lies to you

Once a bad object is stored, the usual Kubernetes tools all say it is fine. This is what makes the failure so slow to find.

| You run | It says | Reality |
| --- | --- | --- |
| `kubectl get` | The object exists | It does |
| `kubectl describe` | No events, no conditions | Istio networking objects have no status field to turn red |
| A request | Behaves as if the object were absent | For the proxies, it is absent |
| `istioctl proxy-status` | Possibly `STALE` for the affected type | The one hint, and easy to miss |

## Where the truth lives

Two places record what really happened: the `istiod` log and the `istiod` metrics. Checking both is the last step of every "I applied it and nothing happened" investigation.

<!-- astrona:playground:renew -->

### Search the log and the reject counters

Search the `istiod` log for rejections, and read the two failure counters:

```sh
kubectl -n istio-system logs deploy/istiod --tail=200 | grep -i -E 'reject|invalid'
kubectl -n istio-system exec deploy/istiod -- \
  curl -s localhost:15014/metrics | grep -E 'pilot_total_xds_rejects|pilot_xds_push_errors'
```

On a healthy playground both commands may print nothing. Remember that these counters are **missing** until they have gone up at least once. So any line appearing at all is the signal; its value is less important.

You can also ask the pre-flight inspector, `istioctl analyze`, which reads every Istio object in a namespace together and reports the ones that cannot work:

```sh
istioctl analyze -n cphealth-demo
```

> [!TIP]
> Re-applying an object that `istiod` already holds does not retry a push. If a change "did nothing", look for the rejection instead of applying it again.

## The investigation order

Put the module together, and you get a short checklist for any suspected control plane problem. Work it top to bottom.

| Step | Check | Question it answers |
| --- | --- | --- |
| 1 | `kubectl -n istio-system get pods -l app=istiod` | Is it ready? How many restarts? How old? |
| 2 | `kubectl -n istio-system logs deploy/istiod` with `grep -iE 'reject\|error\|warn'` | What is it complaining about? |
| 3 | The metrics on port `15014`: pushes, rejects, errors | Is anything reaching the ships? |
| 4 | Make a small change, then repeat steps 1 to 3 | Does a change actually travel? |
| 5 | `istioctl proxy-status` | Did it land on every proxy? |

Step 4 is the one that tells a frozen mesh from a healthy one. Every earlier step can look fine on a control plane that is not doing its job.

## Common pitfalls

> [!WARNING]
> - **Trusting `kubectl apply` output when the validation webhook may have been skipped.** If `istiod` was unreachable when a change was applied, the object can exist and never have been sent.
> - **Expecting `kubectl describe` to show a rejection.** Istio networking objects carry no status conditions. The `istiod` log and `pilot_total_xds_rejects` are the only witnesses.
> - **Re-applying an object because nothing happened.** Re-applying the same content changes nothing and does not retry a push. Fix the rejection.
> - **Reading a missing counter as "cannot tell".** `pilot_total_xds_rejects` appears only after the first rejection. No line means zero.

> *An object that exists is not an object that was sent: the `istiod` log and its reject counter are the only witnesses.*

## Your mission: The Mesh Works And Nothing Can Change

You can now tell a frozen control plane from a healthy one, bring `istiod` back, and find an object that was stored but never sent. Now prove it in a graded mission: traffic flows, nothing can change, and one stored `VirtualService` will never be served.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-030-01
```

Then start the mission:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-01/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-030/module-01/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-016-lab-030-01
astrona start ats-016-playground-030-01
```
