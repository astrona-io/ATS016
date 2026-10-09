# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module gave you three tools for one question: what does all this configuration add up to for one workload, and how do you prove it?

**From [What describe Resolves For One Workload](./course-01-what-describe-resolves.md):**

- `VirtualService` and `DestinationRule` find their target by host and act on the **sending** proxy. `PeerAuthentication` and `AuthorizationPolicy` find it by pod labels and act on the **receiving** proxy.
- `PeerAuthentication` resolves narrowest first, per port: workload beats namespace beats mesh. `AuthorizationPolicy` policies all apply together, `DENY` before `ALLOW`.
- An `ALLOW` policy forbids everything it does not name. One `POST`-only policy turns every `GET` into a `403` from the sidecar.
- `istioctl x describe pod` shows the effective result. Read it to the bottom: an unnamed Service port and a selector that matches nothing are the usual findings.

**From [Making A Proxy Narrate One Decision](./course-02-envoy-log-scopes-at-runtime.md):**

- Envoy's administration interface on `localhost:15000` is behind `istioctl proxy-config`. Changes made through it are runtime state, lost at restart.
- Logging is split into scopes. Raise one, for example `rbac:debug`, on the proxy that makes the decision.
- `enforced denied, matched policy none` means an `ALLOW` policy existed and no rule matched. `shadow` marks a dry-run policy.
- Put the level back with `--level rbac:info`, and run `istioctl proxy-config log` with no `--level` to check.

**From [Capturing A Cluster With bug-report](./course-03-bug-report-and-handover.md):**

- `istioctl bug-report` collects `istiod` logs, Istio resources, events, and every selected proxy's configuration dump, log and statistics.
- Limit it with `--include` and `--since`, or it walks the whole mesh and buries the window that matters.
- Read an archive outside in: cluster context, proxy log, configuration dump, `istiod` logs, events.
- Treat the archive as sensitive, and use it when handing over, when evidence is about to disappear, or when a problem comes and goes.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Widen A Policy Without Weakening The Mesh](./labs/lab-01/README.md) | Making A Proxy Narrate One Decision | find the policy that refuses `GET` with `describe`, allow `GET` while `DELETE` stays refused and mutual TLS stays `STRICT`, and put a forgotten `rbac` log level back to `info` |

If you skipped it, go back to it now. It is short.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. Which proxy applies a <code>VirtualService</code>, and which applies an <code>AuthorizationPolicy</code>?</summary>

The sending (client) proxy applies the `VirtualService`. The receiving (server) proxy enforces the `AuthorizationPolicy`.
</details>

<details>
<summary>2. A mesh-wide <code>PeerAuthentication</code> says <code>PERMISSIVE</code> and a workload one says <code>STRICT</code>. What is the effective mode for that workload?</summary>

`STRICT`. For `PeerAuthentication` the narrowest scope wins, and the workload policy replaces the others for that workload.
</details>

<details>
<summary>3. A namespace has no <code>AuthorizationPolicy</code>. You add one <code>ALLOW</code> policy that permits only <code>POST</code>. What happens to <code>GET</code>?</summary>

It is denied with `403`. Once an `ALLOW` policy selects a workload, any request that matches none of its rules is refused.
</details>

<details>
<summary>4. A <code>GET</code> returns <code>403</code>, and the application log is empty. Why?</summary>

The sidecar on the receiving pod refused the request before it reached the application container.
</details>

<details>
<summary>5. A Service port is named <code>web</code>. What stops working?</summary>

Istio treats the port as plain TCP, so every HTTP feature stops applying: header routing, retries, per-route timeouts, HTTP metrics and `AuthorizationPolicy` rules on methods or paths.
</details>

<details>
<summary>6. On which pod do you raise <code>rbac:debug</code> to see why a request was denied?</summary>

On the destination pod. Authorization is decided by the receiving proxy, so the client's proxy has nothing to log.
</details>

<details>
<summary>7. The <code>rbac</code> log says <code>enforced denied, matched policy none</code>. What does it mean?</summary>

The decision was real (not a dry run), the request was denied, and it matched none of the rules of the `ALLOW` policy that selects the workload.
</details>

<details>
<summary>8. Why pass <code>--since</code> to <code>istioctl bug-report</code>?</summary>

Without it the archive holds the full stored log history of every selected pod, and the few seconds of the incident are buried in hours of unrelated traffic.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-010-02
```

If `astrona list` also showed the mission, remove it the same way:

```sh
astrona destroy ats-016-lab-010-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with `astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-02/playground`. It always starts clean, so nothing you broke carries over.

> *The dossier shows what applies, the officer's own words show why, and the black box keeps it all for someone else.*
