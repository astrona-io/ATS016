# Diagnose Config Sync With proxy-status

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-030/module-02/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-02/playground
> astrona destroy ats-016-playground-030-02
> ```

You applied a `VirtualService`. The analyzer is clean. The object is in the cluster. The request still goes to the wrong place.

At that point there are exactly two possibilities, and they need completely different fixes: either the configuration is wrong, or the configuration never arrived. `istioctl proxy-status` is the command that tells you which, and it takes about two seconds to run. Skipping it is how people spend an afternoon rewriting a rule that was correct all along.

The command is thin — it prints a table. What makes it trustworthy is the protocol underneath: xDS is **acknowledged**, so `istiod` knows, per proxy and per resource type, whether the last thing it sent was accepted, rejected, or never answered. This module is that protocol, the table it produces, and the one state the table cannot show you.

> SYNCED means the proxy acknowledged the config istiod sent. STALE or NOT SENT means the problem is between istiod and the proxy, not in your YAML.

## How this module is organised

1. **[Part 1 — How Configuration Reaches A Proxy](./course-01-xds-and-acknowledgement.md)** — the xDS stream, the four resource types and how they compose, and the ACK/NACK exchange that makes sync state knowable at all.
2. **[Part 2 — Reading The Table](./course-02-reading-the-proxy-status-table.md)** — `SYNCED`, `STALE` and `NOT SENT`; what each rules in and out; and the two right-hand columns that answer questions about revisions and version skew.
3. **[Part 3 — Absence, And The Per-Proxy Diff](./course-03-absence-and-per-proxy-diff.md)** — why a missing row is a diagnosis rather than a gap, the three causes in order of likelihood, and comparing one proxy's live configuration against what `istiod` believes it sent.

## Learning objectives

After this module you can:

- Describe the xDS stream between a proxy and `istiod`, including which side initiates it and on which port.
- Name the four xDS resource types, say what each carries, and explain how they compose into a request path.
- Explain what an ACK and a NACK are, and how they make `proxy-status` possible.
- Read `istioctl proxy-status` output and say what each column reports.
- Distinguish `SYNCED`, `STALE` and `NOT SENT`, and state what each one rules in or out.
- Explain what `SYNCED` does *not* prove.
- Use the output to spot control plane version skew and to confirm which `istiod` revision serves a workload.
- Explain what it means when a workload is missing from the output entirely, and check the three causes in order.
- Run `istioctl proxy-status` against a single proxy to compare what `istiod` sent with what the proxy holds.

## Before you start

You need to be comfortable with `kubectl`. It helps to have read [module 030-01](../module-01/course.md), because this module assumes you already know that `istiod` pushes configuration and that proxies cache what they were last given.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the injected namespace **`proxysync-demo`** containing `notification-service-v1` behind a Service on port 80, plus a `tester` client pod with `curl`. Everything starts healthy and fully synced.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it.

## Where this fits

`proxy-status` is question two of the outside-in sequence, and its whole value is that it partitions the problem:

1. Is the configuration coherent? → `istioctl analyze` ([010-01](../../section-010/module-01/course.md))
2. **Did it reach the proxy?** → `istioctl proxy-status` — this module
3. If yes, what is the proxy doing with it? → `istioctl proxy-config` ([section 040](../../section-040/module-01/course.md))

A `SYNCED` row sends you to question three and eliminates an entire class of causes. A `STALE` row or a missing row sends you back toward the control plane and the pod, and tells you not to touch your YAML at all.
