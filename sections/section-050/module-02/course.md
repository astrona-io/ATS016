# Debug A 503 Caused By An mTLS Mismatch

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-050/module-02/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-02/playground
> astrona destroy ats-016-playground-050-02
> ```

Mutual TLS in Istio is configured from two ends by two different objects, usually written by two different people. `PeerAuthentication` says what the **server** will accept. `DestinationRule` says what the **client** will send. Neither object references the other, neither is invalid on its own, and the analyzer will not always object.

The contrast that makes this module worth a section of its own: every other `503` in this course is a failure to *find* a destination, visible in configuration the client holds. This one is a failure to *agree* with a destination that was found perfectly well — and its evidence is as much in what is missing from one log as in what is present in the other.

> A STRICT server plus a client DestinationRule that disables TLS is a guaranteed failure, and nothing in either object looks wrong on its own.

## How this module is organised

1. **[Part 1 — Two Objects, Two Ends Of One Connection](./course-01-two-objects-two-ends.md)** — which object configures which side, every mode on both, the combinations that fail, and what those settings become inside Envoy.
2. **[Part 2 — The Signature](./course-02-the-signature.md)** — the `UF`-with-a-silent-destination pattern, why the handshake fails before any HTTP exists to log, and reading the effective mode rather than a single object.
3. **[Part 3 — Fixing It, And Proving Encryption](./course-03-fixing-and-proving-encryption.md)** — which end to change and why, the fix that removes configuration rather than adding it, proving traffic is encrypted rather than merely working, and the variant with no `DestinationRule` at all.

## Learning objectives

After this module you can:

- Name the object that configures each side of mTLS and the field each one uses.
- List the modes on both sides and predict which combinations work.
- Explain what `PERMISSIVE` does and why it makes mismatches survive unnoticed.
- Recognise the `UF`-on-the-client, nothing-on-the-server signature and explain why the destination logs nothing.
- Read a workload's effective mTLS mode rather than a single policy object.
- Decide which of the two objects to change, and justify not changing the other.
- Prove traffic is encrypted after the fix, rather than merely working.
- Recognise the same signature produced by a caller that is outside the mesh, and fix it correctly.

## Before you start

You need [module 050-01](../module-01/course.md) — this module is an applied reading of the access log, and the `UF` flag plus the two-proxy comparison are central to it. It also helps to know `istioctl x describe pod` from [module 010-02](../../section-010/module-02/course.md), and the inbound filter chains from [module 040-01 Part 4](../../section-040/module-01/course-04-inbound-secrets-and-method.md).

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the injected namespace **`mtlsfail-demo`** containing:

- `notification-service-v1` behind the Service `notification-service` on port 80.
- `tester` — a client pod with `curl`.
- A `PeerAuthentication` and a `DestinationRule` that are **already in conflict**. Diagnosing that is the module's subject.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it.

## Where this fits

This module completes section 050's method: read the flag, read *which proxy* logged it, then read what each end was configured to do.

The `UF`-with-silent-destination pattern is worth committing to memory, because it is the one signature in Istio that points at a small, specific set of causes: an mTLS mode mismatch, a caller outside the mesh, or a port with no declared protocol. All three are configuration problems between two healthy workloads, and none of them will ever appear in an application log.
