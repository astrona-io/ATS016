# Debug A 503 Caused By A Missing Subset

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-040/module-02/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/module-02/playground
> astrona destroy ats-016-playground-040-02
> ```

`503 Service Unavailable` is the most common failure in an Istio mesh and the least informative on its own. It can mean the application crashed. It can mean nothing was ever running. It can also mean — and in a mesh, usually does — that the proxy had nowhere to send the request, because the destination it was told to use does not exist.

The contrast that organises this module: a `503` from your **application** and a `503` from the **proxy in front of it** are byte-for-byte identical to the client, and they need completely different investigations. One question separates them, and it takes one command. This module works a single instance end to end — a `VirtualService` routing to a subset no `DestinationRule` defines — but the method is the point, and it generalises to every `503` you will meet.

> A route to a subset with no DestinationRule produces a cluster with nothing behind it, and a proxy with nowhere to send a request answers 503.

## How this module is organised

1. **[Part 1 — Who Answered With 503](./course-01-who-answered-with-503.md)** — separating a proxy-generated failure from an application one, the response flag field, and what each flag in the `503` family points at.
2. **[Part 2 — Walking The Chain](./course-02-walking-the-chain.md)** — the analyzer's fast path, then route → cluster → endpoint by hand, carrying each name to the next command, and the two different kinds of empty answer.
3. **[Part 3 — Choosing The Fix, And The Other Cause](./course-03-choosing-the-fix.md)** — which end of a dangling reference to change and why it matters, proving a fix from three directions, and the unnamed-Service-port failure that produces the same symptom from nowhere near the same place.

## Learning objectives

After this module you can:

- Read a `503` as a statement about the proxy rather than about the application, and prove which one answered.
- Find the response flag in an Envoy access log line and say what `NC`, `UH`, `NR`, `UF`, `UC` and `-` each indicate.
- Explain why a failing request leaves no trace on the destination proxy.
- Follow the route → cluster → endpoint chain to the exact link that is missing.
- Distinguish a missing cluster from an empty one, and name the flag that tells them apart.
- Decide whether to change the route or define the missing subset, and justify the choice.
- Verify a fix with traffic, the proxy's own configuration, and the analyzer.
- Recognise a Service port with no declared protocol as a second cause of the same symptom.

## Before you start

You need [module 040-01](../module-01/course.md): the four stages, the `istioctl proxy-config` subcommands, and the `direction|port|subset|fqdn` cluster naming convention are all assumed here.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the injected namespace **`fivezerothree-demo`** containing:

- `notification-service-v1` — a Deployment labelled `version: v1`, behind the Service `notification-service` on port 80.
- `tester` — a client pod with `curl`.
- A `DestinationRule` and a `VirtualService` that are **already broken**, in the specific way this module diagnoses. Work the chain before reading `playground/manifests/`.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it.

## Where this fits

This module is section 040's method applied under time pressure, and the order is what makes it fast:

1. **Read the response flag** before forming any theory — it says whether the proxy or the application answered, and which layer failed.
2. **Run the analyzer** — for reference errors it frequently names the object outright.
3. **Follow route → cluster → endpoint**, carrying each name to the next command.
4. **Fix one thing**, then re-verify with both traffic and the chain.

[Section 050](../../section-050/module-01/course.md) takes the access log apart properly — every field, not just the flag — and applies the same method to failures that happen *after* a connection is established.
