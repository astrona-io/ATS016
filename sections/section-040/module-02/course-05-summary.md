# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about one failure, a `503` from a route to a subset nobody built, and the method that finds it and every `503` like it.

**From [Who Answered With 503](./course-01-who-answered-with-503.md):**

- A `503` from a proxy and a `503` from the app look the same to the client. The response flag in the client proxy's access log tells them apart.
- `NC` means no cluster, `UH` no healthy endpoint, `NR` no route, `UF` a connection that failed, `UC` a connection that dropped, and `-` means the app itself answered.
- An empty destination log means the request never arrived, so the investigation stays on the sending side.

**From [Walking The Chain](./course-02-walking-the-chain.md):**

- `istioctl analyze` often names a dangling reference outright, with `IST0101`.
- The manual chain still works where the analyzer is silent: route (which cluster is named), cluster (does it exist), endpoints (does it have anything).
- A missing cluster (`NC`) and an empty cluster (`UH`) both show an empty endpoint list; only the cluster step tells them apart.

**From [Choosing And Proving The Fix](./course-03-choosing-and-proving-the-fix.md):**

- Fix the end of a dangling reference that matches reality. Check the pod labels first.
- Inventing a subset whose labels match no pod turns `NC` into `UH`: the analyzer goes quiet and the traffic still fails.
- Prove a fix three ways: a real request, the proxy's route table, and a clean analyzer run.

**From [The Other Cause: An Undeclared Port](./course-04-the-other-cause-an-undeclared-port.md):**

- Istio reads a port's protocol from its `name` or `appProtocol`. An undeclared port is treated as TCP, and HTTP routing rules never apply.
- The listener shows it: an HTTP port hands off to a `Route:`, a TCP port straight to a `Cluster:`.
- The fix is to name the port (for example `http`), with no restart and no change to the port numbers.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Trace A 503 To Its Exact Stage](./labs/lab-01/README.md) | Choosing And Proving The Fix | trace a `503` from its flag to the missing cluster, and fix the route without inventing a subset |

If you skipped it, go back to it now. It is short.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. A request returns <code>503</code> and the destination pod is <code>2/2 Running</code> with no restarts. What is the first command you run?</summary>

Read the client proxy's access log, for example `kubectl -n <ns> logs deploy/tester -c istio-proxy --tail=5`, and find the response flag. It tells you whether a proxy or the app answered, and which stage failed.
</details>

<details>
<summary>2. The response flag is <code>-</code>. Where do you look next?</summary>

At the app. A `503` with flag `-` is the app's own answer, passed on by the proxy. Istio debugging will not explain it.
</details>

<details>
<summary>3. The client log shows a failure and the destination's log shows nothing. What does that mean?</summary>

The request never arrived. The cause is on the sending side: routing, clusters, endpoints, or the connection itself.
</details>

<details>
<summary>4. The route names <code>outbound|80|v2|...</code> and <code>proxy-config cluster</code> lists no <code>v2</code> row. Which flag do you expect?</summary>

`NC`, no cluster. The route names a cluster that does not exist.
</details>

<details>
<summary>5. Why is adding a <code>v2</code> subset to the <code>DestinationRule</code> the wrong fix here?</summary>

No pod carries `version: v2`. The new subset creates a cluster with no endpoints, so the flag changes from `NC` to `UH`, the analyzer goes quiet, and the traffic still fails.
</details>

<details>
<summary>6. Does a <code>VirtualService</code> change need a pod restart to take effect?</summary>

No. `istiod` pushes the new routes over xDS and the proxy swaps them in place within a second or two. If the change seems not to land, check `istioctl proxy-status`.
</details>

<details>
<summary>7. A Service port is named <code>web</code>, and a <code>VirtualService</code> for it is ignored. Why?</summary>

`web` declares no protocol, so Istio treats the port as TCP. No HTTP route is built for it, and the listener hands straight to a cluster. Name the port `http` (or set `appProtocol: http`).
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-040-02
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-016-lab-040-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *Flag first, then the chain, then the fix that matches reality: that is how every 503 gives up its cause.*
