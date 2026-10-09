# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the flight log every communications officer keeps: the Envoy access log, and the response flag stamped on each failed signal.

**From [Turning Logging On, And Scoping It](./course-01-enabling-and-scoping-logs.md):**

- `meshConfig.accessLogFile: /dev/stdout` switches logging on for the whole mesh; a `Telemetry` object switches it on for the root namespace, one namespace, or selected workloads.
- The narrowest scope wins, and `disabled: true` silences one chatty workload.
- A CEL `filter` such as `response.code >= 400` keeps only some lines, but during an investigation you want the successful lines too.
- The logs are container output: read them with `kubectl logs <pod> -c istio-proxy`, and they disappear with the pod.

**From [The Anatomy Of A Line](./course-02-anatomy-of-a-log-line.md):**

- Six fields carry the diagnosis: status and flag, response code details, the duration pair, authority, upstream host and upstream cluster.
- `via_upstream` means the application answered; a proxy-made answer never touched your application.
- An upstream host of `-` means no connection was attempted.
- The request id (`x-request-id`) is the same on both proxies' lines, so you can find one request on both sides.

**From [Flags, And Which Proxy Wrote The Line](./course-03-flags-and-which-proxy.md):**

- `U` flags are about the destination, `D` flags about the client, `N` flags mean the proxy could not decide where to go.
- `NR`, `NC`, `UH`, `UO`, `UF`, `UC`, `UT` are positions on the path, from "never chose a destination" to "connected and never got an answer".
- `-` with an error status points at the application.
- The upstream cluster field shows the side: `outbound|…` on the client, `inbound|…` on the destination.

**From [Failures The Client's Proxy Decides](./course-04-failures-the-client-proxy-decides.md):**

- `UT` comes with a `504`, `UO` with a `503` and a duration of `0`, `NR` with a `404`.
- All three have an upstream host of `-`: the sending ship's proxy decided, and the destination never saw the request.
- A fault delay and a timeout on the same rule may never meet, because the fault filter runs before the router.

**From [A Denial On The Other Proxy](./course-05-a-denial-on-the-other-proxy.md):**

- An authorization denial shows `403` with the flag `-` on both sides.
- Only the destination's response code details name the policy and rule: `rbac_access_denied_matched_policy[...]`.
- A count of flags over a window shows which failure is most common.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Scope The Logs, Bound The Latency, Name The Flag](./labs/lab-01/README.md) | Failures The Client's Proxy Decides | scope logging with a `Telemetry` object, set a 2-second route timeout, and find the `UT` flag it produces |

If you skipped it, go back to it now. The mission is short.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. Why is a <code>Telemetry</code> object better than <code>meshConfig.accessLogFile</code> during an investigation?</summary>

It belongs to one namespace (or selected workloads), you remove it with `kubectl delete`, and it needs no install change or control plane restart. The mesh-wide setting switches on logs for every proxy at once.
</details>

<details>
<summary>2. A line shows <code>503</code> and the flag <code>-</code>. Where do you look?</summary>

At the application. `-` means no proxy-level error happened, so the application produced the `503` itself.
</details>

<details>
<summary>3. What does an upstream host of <code>-</code> tell you?</summary>

That the proxy never attempted a connection. The failure happened before any network activity, for example no route, no cluster, a circuit breaker or a timeout decided on the client side.
</details>

<details>
<summary>4. You see many <code>UO</code> flags. Is the destination down?</summary>

Not necessarily. `UO` (upstream overflow) means your own `DestinationRule` `connectionPool` limits rejected the request. The destination may be idle. The duration of `0` milliseconds shows the request was refused at once.
</details>

<details>
<summary>5. How do you tell from one line whether it was written by the client or by the destination proxy?</summary>

Read the upstream cluster field. The client's proxy writes `outbound|80||notification-service...`; the destination's proxy writes `inbound|8084||`.
</details>

<details>
<summary>6. A request is denied with <code>403</code>. Which proxy's log names the policy that refused it?</summary>

The destination's. Its response code details read `rbac_access_denied_matched_policy[ns[...]-policy[...]-rule[...]]`. The client's line just shows an ordinary `403` with the flag `-`.
</details>

<details>
<summary>7. A request returns <code>404</code> with the flag <code>NR</code>, but your route rule looks right. What else can cause it?</summary>

The `Host` header did not match any route (check the authority field), the Service port declares no protocol so no HTTP route was built, or the `VirtualService` is bound to a gateway while the traffic stays inside the mesh.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-050-01
```

If `astrona list` also showed the mission, remove it the same way:

```sh
astrona destroy ats-016-lab-050-01
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with `astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-01/playground`. It always starts clean, so nothing you broke carries over.

> *Read the flag, then ask which proxy wrote the line: together they tell you where the signal stopped.*
