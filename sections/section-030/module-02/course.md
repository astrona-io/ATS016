# Diagnose Configuration Sync With proxy-status

Astronaut, you applied a `VirtualService` (a flight plan). The pre-flight inspector, `istioctl analyze`, is happy. The object is in the cluster. And the signal still flies to the wrong place.

At that point there are exactly two possibilities, and they need different fixes: either the configuration is wrong, or the configuration never arrived. `istioctl proxy-status` tells you which, in about two seconds. It is mission control's roll call: it lists every ship's communications officer (sidecar proxy) that answers, and whether each one holds the latest orders.

The command only prints a table. What makes the table trustworthy is the protocol underneath it. Every order `istiod` sends must be confirmed: the officer radios back "orders received" (an ACK) or "orders rejected, keeping the old ones" (a NACK). This module is that protocol, the table it produces, and the one state the table cannot show.

> `SYNCED` means the proxy confirmed the configuration `istiod` sent. `STALE`, or a missing row, means the problem is between `istiod` and the proxy, not in your YAML.

## Learning objectives

After this module you can:

- Describe the xDS stream between a proxy and `istiod`, including which side starts it and on which port.
- Name the four xDS resource types, say what each carries, and explain how they fit together into a request path.
- Explain what an ACK and a NACK are, and how they make `istioctl proxy-status` possible.
- Read `istioctl proxy-status` output and say what each column reports.
- Tell `SYNCED`, `STALE` and `NOT SENT` apart, and say what each one rules in or out.
- Explain what `SYNCED` does *not* prove.
- Use the output to spot version skew and to confirm which `istiod` serves a workload.
- Explain what it means when a workload is missing from the output, and check the three causes in order.
- Run `istioctl proxy-status` against one proxy to compare what `istiod` sent with what the proxy holds.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** You can use `kubectl` to list pods, read logs and change labels.
- **What `istiod` does.** `istiod` is mission control: it pushes configuration to every proxy, and each proxy keeps the last configuration it was given.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` ready to use. It has one planet (namespace), **`proxysync-demo`**, with injection switched on:

| Ship | What it does |
| --- | --- |
| `notification-service-v1` | The app, behind the beacon (Service) `notification-service` on port `80` |
| `tester` | Your test ship: a client pod with `curl` |

Everything starts healthy, and every proxy starts fully `SYNCED`. Making one disappear from the roll call is up to you.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts, in order

1. [How Configuration Reaches A Proxy](./course-01-xds-and-acknowledgement.md)
2. [Reading The Table](./course-02-reading-the-proxy-status-table.md)
3. [Absence, And The Per-Proxy Diff](./course-03-absence-and-per-proxy-diff.md)
4. [Wrap-Up: Mission Debrief](./course-04-wrap-up.md)

## Why this matters

`istioctl proxy-status` splits every "my change did nothing" problem in two. A `SYNCED` row says the configuration arrived, so you look at what the proxy does with it. A `STALE` row or a missing row says it did not arrive, so you leave your YAML alone and look at the control plane and the pod. Two seconds of checking saves an afternoon of rewriting a rule that was correct all along.
