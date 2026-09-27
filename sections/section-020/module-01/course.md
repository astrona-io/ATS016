# Debug Conflicting And Shadowed Routes

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-020/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-020/module-01/playground
> astrona destroy ats-016-playground-020-01
> ```

A header-based route is the first thing most people write in Istio, and it is also the first thing that silently stops working. The YAML is correct. `kubectl apply` is happy. `istioctl analyze` may say nothing at all. The request still lands on the wrong version.

Two separate causes produce that identical symptom, and they need different fixes. Inside one `VirtualService`, a rule can be **shadowed** by a rule above it, because the list is evaluated in order and the first match wins. Across two `VirtualService` objects, the same host can be claimed twice and **merged** in an order you did not choose. This module takes both apart at the level of what the proxy actually ends up holding — which is where the habit that matters is formed: when the route table disagrees with your YAML, the YAML is not the whole story.

> Two VirtualServices for the same host are merged unpredictably, and inside one VirtualService the first matching rule wins.

## How this module is organised

1. **[Part 1 — How A VirtualService Becomes A Route Table](./course-01-virtualservice-to-route-table.md)** — the translation from your object into Envoy's ordered route list, why a rule with no `match` is unconditional rather than a fallback, and what shadowing costs.
2. **[Part 2 — One Host, Two Owners](./course-02-host-ownership-and-merging.md)** — what Istio does when two objects claim the same host, why the result is undefined rather than wrong, how gateway binding scopes ownership, and what `IST0109` is telling you.
3. **[Part 3 — The Route Table Is The Ground Truth](./course-03-reading-the-route-table.md)** — reading the proxy's live route configuration, locating a shadowed rule in it, applying the two-part fix, and verifying both paths.

## Learning objectives

After this module you can:

- Describe how a `VirtualService` is translated into Envoy route configuration, and name the objects at each stage.
- Explain how `http` rules are evaluated, and why a rule with no `match` ends the list.
- Place a catch-all route correctly and predict what happens when it is placed first.
- Describe what Istio does when two `VirtualService` objects declare the same host, and why the resulting order should not be relied on.
- Use gateway binding to scope host ownership so two objects do not overlap.
- Read the effective route order out of a running proxy with `istioctl proxy-config routes`.
- Diagnose a misrouted request by comparing the proxy's route table against the configuration you believe is in force.
- Verify a routing fix from both ends — the matched path and the default path.

## Before you start

You need to know what a `VirtualService` and a `DestinationRule` are, and what a subset is. You do not need to have written a routing rule before — this module is about the rules going wrong, which teaches the mechanism more sharply than the happy path does.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the injected namespace **`conflict-demo`** containing:

- `notification-service-v1` and `notification-service-v2` — two Deployments behind one Service, `notification-service`, on port 80. They are distinguishable by their response: `v1` answers `["EMAIL"]`, `v2` answers `["EMAIL","SMS"]`.
- `tester` — a client pod with `curl`.
- A `DestinationRule` defining subsets `v1` and `v2`, and **two `VirtualService` objects that are deliberately in conflict**.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it.

## Where this fits

This module is the first place where the proxy is treated as the authority rather than the API server. The outside-in order from [section 010](../../section-010/module-01/course.md) still holds — is the configuration coherent, did it reach the proxy, what is the proxy doing — but conflicting routes are the case where the first question can answer "coherent enough" while the behaviour is still wrong.

`istioctl proxy-config routes` appears here for the first time, used narrowly. [Section 040](../../section-040/module-01/course.md) takes the same command apart properly, across listeners, routes, clusters and endpoints, and shows how to follow a request through all four stages.
