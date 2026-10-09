# Section 020: Debugging Conflicting And Shadowed Routes

A header-based route is often the first thing people write in Istio, and the first thing that quietly stops working. The YAML is correct, the object exists, and the request still reaches the wrong version of the service.

Two different mistakes cause that same symptom. Inside one `VirtualService`, the Istio resource that holds the routing rules for a host, the rules are checked from the top. A rule with no `match` catches every request, so every rule below it is shadowed and never checked. Across two `VirtualService` objects, the same host can be claimed twice, and the sidecar proxy then uses only one of them, chosen by an order nobody wrote down. This section covers both. It also builds the habit you need for every routing problem: when the proxy's route table disagrees with your YAML, the YAML is not the whole story.

**Exam topic covered:** Troubleshooting Configuration

## What you will learn

- How the `http` list of a `VirtualService` is checked, and why a rule without `match` ends it.
- Where a catch-all route belongs, and what happens when it is placed first.
- What Istio does when two `VirtualService` objects declare the same host, and why the `IST0109` message matters.
- How to read the real route order from a proxy with `istioctl proxy-config routes`.
- How to find a misrouted request by comparing the route table with the configuration you believe is in force.
- How to check a routing fix from both ends: the matched path and the default path.

## The module

The section has one module, **Debug Conflicting And Shadowed Routes**. Its landing page launches the playground: the namespace `conflict-demo`, with two versions of `notification-service`, a `tester` client pod, and two `VirtualService` objects in conflict on purpose. The two versions answer differently, so the reply tells you which one answered.

The module has three parts, read in this order:

1. How A VirtualService Becomes A Route Table
2. One Host, Two Owners
3. The Route Table Is The Ground Truth, followed by the lab **Make The Header Route Actually Fire**

A summary closes the module and removes the playground.

## Section capstone

The capstone, **Consolidate Three Claimants Into One Route Table**, is one graded scenario that puts the whole section to work. Three teams have each added a `VirtualService` for `notification-service` in the namespace `routing-demo`, and one of them shadows its own header rule. You combine them into one route table where a header, a path prefix and a catch-all each reach the right version. Work it after the module lab.

Start it:

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-020/capstone/labs/lab-01
```

When you are done, send it for grading:

```bash
astrona submit -c sections/section-020/capstone/labs/lab-01
```

Then remove it:

```bash
astrona destroy ats-016-capstone-020
```
