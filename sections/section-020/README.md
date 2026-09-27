# Section 020: Debugging Conflicting And Shadowed Routes

A header-based route is the first thing most people write in Istio and the first thing that silently stops working. The YAML is correct, the object exists, and the request lands on the wrong version.

Two different mistakes produce that identical symptom. Inside one `VirtualService`, rules are evaluated top down and a rule with no `match` is unconditional — so anything below it is unreachable. Across two `VirtualService` objects, the same host can be claimed twice, and Istio merges them in an order nobody chose. This section covers both, and introduces the habit the rest of the course depends on: when the proxy's route table disagrees with your YAML, the YAML is not the whole story.

**Curriculum item covered:** Troubleshooting Configuration

---

## What You Will Master

- How a `VirtualService`'s `http` list is evaluated, and why a rule without `match` ends it.
- Where a catch-all route belongs, and what happens when it is placed first.
- What Istio does when two `VirtualService` objects declare the same host, and why `IST0109` is a Warning you cannot ignore.
- Reading the effective route order from a proxy with `istioctl proxy-config routes`.
- Diagnosing a misrouted request by comparing the route table against the configuration you believe is in force.
- Verifying a routing fix from both ends — the matched path and the default path.

---

## The Learning Path

### 1. Debug Conflicting And Shadowed Routes
*   **Module Reader:** **[Module 1: Debug Conflicting And Shadowed Routes](./module-01/course.md)**
    *   Deep dive, in order:
        1. [How A VirtualService Becomes A Route Table](./module-01/course-01-virtualservice-to-route-table.md)
        2. [One Host, Two Owners](./module-01/course-02-host-ownership-and-merging.md)
        3. [The Route Table Is The Ground Truth](./module-01/course-03-reading-the-route-table.md)
*   **Hands-on Playground:** `sections/section-020/module-01/playground` — a kind cluster with Istio installed and namespace `conflict-demo`, holding two versions of one service, a client pod, and two `VirtualService` objects in deliberate conflict. The two versions answer differently, so you can tell from the response body which one replied.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-020/module-01/playground
    ```
*   **Graded Lab:** **[Make The Header Route Actually Fire](./module-01/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-020/module-01/labs/lab-01
    ```

The playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear it down with `astrona destroy <name>` when you are finished — the name is printed in the module's playground callout.

---

## Section Capstone

**[Consolidate Three Claimants Into One Route Table](./capstone/labs/lab-01/question.md)** — one graded scenario
combining this section's modules, with several independent faults to find and
fix. Work it after the module labs.

> Three teams have each added a `VirtualService` for `notification-service` in `routing-demo` over the past year. `v1` answers `["EMAIL"]`; `v2` answers `["EMAIL","SMS"]`.

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-020/capstone/labs/lab-01
astrona submit
```
