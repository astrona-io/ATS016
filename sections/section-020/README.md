# Section 020: Debugging Conflicting And Shadowed Routes

Astronaut, a header-based route is often the first thing people write in Istio, and the first thing that quietly stops working. The YAML is correct, the object exists, and the signal (the request) still lands on the wrong version.

Two different mistakes cause that same symptom. Inside one `VirtualService` (a flight plan for a beacon), the rules are read from the top, and a rule with no `match` catches every signal, so anything below it can never be reached. Across two `VirtualService` objects, the same host can be claimed twice, and Istio merges them in an order nobody chose. This section covers both. It also builds the habit you need for every routing problem: when the proxy's route table disagrees with your YAML, the YAML is not the whole story.

**Exam topic covered:** Troubleshooting Configuration

## What you will learn

- How the `http` list of a `VirtualService` is checked, and why a rule without `match` ends it.
- Where a catch-all route belongs, and what happens when it is placed first.
- What Istio does when two `VirtualService` objects declare the same host, and why the `IST0109` Warning matters.
- How to read the real route order from a proxy with `istioctl proxy-config routes`.
- How to find a misrouted request by comparing the route table with the configuration you believe is in force.
- How to check a routing fix from both ends: the matched path and the default path.

## The module

### Debug Conflicting And Shadowed Routes

Start with the module's landing page: [Debug Conflicting And Shadowed Routes](./module-01/course.md). Its playground runs the planet `conflict-demo`, with two versions of `notification-service`, a `tester` client, and two `VirtualService` objects in conflict on purpose. The two versions answer differently, so the reply tells you which one answered.

Read the parts in this order:

1. [How A VirtualService Becomes A Route Table](./module-01/course-01-virtualservice-to-route-table.md)
2. [One Host, Two Owners](./module-01/course-02-host-ownership-and-merging.md)
3. [The Route Table Is The Ground Truth](./module-01/course-03-reading-the-route-table.md), followed by the mission **[Make The Header Route Actually Fire](./module-01/labs/lab-01/question.md)**
4. [Wrap-Up: Mission Debrief](./module-01/course-04-wrap-up.md)

The playground is ungraded: it starts, prepares the planet, and waits. Each landing page shows how to launch it, and the wrap-up shows how to remove it.

## Section capstone

**[Consolidate Three Claimants Into One Route Table](./capstone/labs/lab-01/question.md)** is one graded scenario that puts the whole section to work. Three teams have each added a `VirtualService` for `notification-service` in `routing-demo`, and one of them hides its own header rule. You merge them into one route table where a header, a path prefix and a catch-all all reach the right version. Work it after the module mission.

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
