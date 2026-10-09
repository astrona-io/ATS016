# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about mission control's roll call: `istioctl proxy-status`, and the confirmed delivery of orders that makes it possible.

**From [How Configuration Reaches A Proxy](./course-01-xds-and-acknowledgement.md):**

- Envoy does not read Kubernetes. `pilot-agent` in the `istio-proxy` container dials out to `istiod.istio-system.svc:15012` and holds a long-lived xDS stream.
- The four main types are `LDS` (listeners), `RDS` (routes), `CDS` (clusters) and `EDS` (endpoints), used in that order for every signal.
- Every push is answered: an ACK repeats the new version; a NACK repeats the old version and the proxy keeps its previous configuration.
- `SYNCED` means ACK, `STALE` means no answer yet or a NACK, `NOT SENT` means nothing to send.

**From [Reading The Table](./course-02-reading-the-proxy-status-table.md):**

- `SYNCED` proves delivery, not correctness. Wrong configuration synchronises perfectly.
- `NOT SENT` is normal for `RDS` on a proxy with no HTTP routes and for `ECDS` with no extensions.
- A short `STALE` is normal; run the command twice. A lasting `STALE` is usually a NACK.
- The `ISTIOD` column proves which revision serves a proxy; the `VERSION` column shows skew. A proxy may be at most one minor version behind `istiod`, never ahead.

**From [Absence, And The Per-Proxy Diff](./course-03-absence-and-per-proxy-diff.md):**

- There is no `DISCONNECTED` row. A missing row has three causes: no sidecar, no link to `istiod`, or no `istiod`.
- Count containers first: `1/1` means no sidecar.
- Removing the injection label and restarting made a workload vanish; restoring both brought it back `SYNCED`.
- `istioctl proxy-status <pod>.<namespace>` compares `istiod`'s record with the proxy's live configuration and prints `Match` or a diff.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [One Workload Vanished From The Mesh](./labs/lab-01/README.md) | Absence, And The Per-Proxy Diff | find why a workload is missing from the roll call, fix it so the fix survives pod replacement, and prove it reconnected |

If you skipped it, go back to it now.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. Which side starts the xDS connection, and on which port?</summary>

The proxy. `pilot-agent` in the `istio-proxy` container dials out to `istiod.istio-system.svc:15012`. `istiod` never connects to a pod.
</details>

<details>
<summary>2. A proxy rejects a new configuration. What does it run afterwards?</summary>

The last configuration it accepted. A NACK keeps the previous version running, so the symptom is "nothing changed", not an outage.
</details>

<details>
<summary>3. Every row says <code>SYNCED</code>, but requests still go to the wrong version. Where is the problem?</summary>

In the configuration itself. `SYNCED` only proves the proxy accepted what it was sent. Look at what the proxy made of it with `istioctl proxy-config`.
</details>

<details>
<summary>4. The ingress gateway shows <code>RDS: NOT SENT</code>. Is it broken?</summary>

No. No `Gateway` or `VirtualService` is bound to it, so there are no HTTP routes to send.
</details>

<details>
<summary>5. A row shows <code>STALE</code>. What do you do first?</summary>

Run the command again a few seconds later. If it stays `STALE`, look for a NACK: a `reject` line in the `istiod` log and the `pilot_total_xds_rejects` counter.
</details>

<details>
<summary>6. A workload is missing from <code>istioctl proxy-status</code> and its pod shows <code>1/1</code>. Should you check network policies?</summary>

No. `1/1` means there is no sidecar, so there is no proxy to connect. Find out why injection did not happen.
</details>

<details>
<summary>7. A workload is missing and its pod shows <code>2/2</code>. Where do you look?</summary>

At the link to `istiod` on port `15012`. Search the `istio-proxy` log for `xds`, `15012` or `connect`; repeated connection errors name the destination to unblock.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-030-02
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-016-lab-030-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time from the module's landing page. It always starts clean, so nothing you broke carries over.

> *The roll call lists the ships that answer: a missing ship is your first clue, not a gap in the data.*
