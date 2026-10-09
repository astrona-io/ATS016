# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about mission control itself: `istiod`, the control plane that serves every communications officer (sidecar proxy) their orders and badges.

**From [Four Jobs In One Process](./course-01-the-four-jobs-of-istiod.md):**

- `istiod` does four jobs: xDS server (orders), certificate authority (badges), injection webhook (launch-pad crew) and validation webhook (registry clerk).
- Proxies call `istiod` for orders and badges; the API server calls `istiod` for injection and validation.
- Without a control plane, running proxies keep their orders and badges, so traffic flows but nothing can change.
- Certificates usually last about 24 hours, so a long outage breaks mutual TLS everywhere at once, long after it started.

**From [The Instruments](./course-02-instruments-logs-and-metrics.md):**

- Readiness and liveness only ask "is the server answering?". A climbing `RESTARTS` count on a `Running` pod is a crash loop, often `OOMKilled`.
- The `istiod` log tells the story of its pushes; scan it for `reject`, `error` and `warn`.
- The metrics on port `15014` include `pilot_xds_pushes`, `pilot_xds_push_errors`, `pilot_total_xds_rejects` and `pilot_proxy_convergence_time`.
- Counters only go up, reset on restart, and are missing until their first increase.

**From [Take Mission Control Away](./course-03-take-mission-control-away.md):**

- With `istiod` scaled to zero, an existing signal still returned `200`.
- A restarted Deployment could not create its new pod, because the injection webhook's `failurePolicy: Fail` refused it.
- `failurePolicy: Ignore` would have started the pod with no sidecar, quietly outside the mesh.
- Scaling `istiod` back up was enough: the mesh caught up by itself.

**From [Accepted, Never Applied](./course-04-accepted-never-applied.md):**

- An invalid object can be stored when the validation webhook was skipped, and `istiod` then never sends it.
- A proxy can also refuse orders with a NACK and keep its old ones.
- `kubectl get` and `kubectl describe` show nothing wrong; the `istiod` log and `pilot_total_xds_rejects` are the witnesses.
- Check in order: pod status, log, metrics, a small test change, then `istioctl proxy-status`.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [The Mesh Works And Nothing Can Change](./labs/lab-01/README.md) | Accepted, Never Applied | bring `istiod` back, find and remove the stored object it refuses, and show every proxy `SYNCED` |

If you skipped it, go back to it now.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. Traffic is flowing normally. Does that prove <code>istiod</code> is healthy?</summary>

No. Proxies route with the orders they already hold and handshake with badges they already have. Test a change instead: restart a pod or change a route, and see whether it takes effect.
</details>

<details>
<summary>2. Which two jobs of <code>istiod</code> does the API server call, and which two do the proxies call?</summary>

The API server calls the injection webhook and the validation webhook. The proxies call the xDS server for orders and the certificate authority for badges.
</details>

<details>
<summary>3. <code>istiod</code> shows <code>1/1 Running</code> with <code>RESTARTS 14</code>. What is going on?</summary>

A crash loop that Kubernetes keeps hiding by restarting the container, most often because it runs out of memory. Check the last termination reason for `OOMKilled`.
</details>

<details>
<summary>4. <code>pilot_total_xds_rejects</code> does not appear in the metrics at all. Is the metric broken?</summary>

No. A counter that has never gone up is usually not shown. A missing line means no proxy has rejected anything, which is good news.
</details>

<details>
<summary>5. During an <code>istiod</code> outage you restart a Deployment. What happens with the default <code>failurePolicy</code>?</summary>

With `Fail`, the API server cannot reach the injection webhook and refuses to create the new pod. The old pod keeps running. With `Ignore`, the pod would start without a sidecar.
</details>

<details>
<summary>6. You applied a <code>VirtualService</code>, <code>kubectl get</code> lists it, and nothing changed. Where do you look?</summary>

In the `istiod` log for `reject` or `invalid`, and in the metrics for `pilot_total_xds_rejects` and `pilot_xds_push_errors`. `istioctl analyze` can also name the invalid object.
</details>

<details>
<summary>7. <code>istiod</code> comes back after an outage. Do you need to re-apply your configuration?</summary>

No. A pure outage delays changes, it does not lose them. The proxies reconnect and receive the current orders by themselves.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-030-01
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-016-lab-030-01
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time from the module's landing page. It always starts clean, so nothing you broke carries over.

> *Mission control can be down while every ship still flies: test change, not traffic.*
