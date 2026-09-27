# Section 040: Reading Data Plane Configuration

By this point in an investigation the configuration is coherent, the proxy received it, and the workload is in the mesh — and the request still does the wrong thing. There is nowhere left to look except inside Envoy.

That is less daunting than it sounds, because Envoy handles a request in four stages in a fixed order, and `istioctl proxy-config` has one subcommand per stage. Module 1 walks all four on a working proxy, because you cannot recognise a wrong configuration until you know what a right one looks like. Module 2 applies the same chain to the most common failure in the mesh: a `503` from a route pointing at a destination that does not exist.

**Curriculum item covered:** Troubleshooting the Mesh Data Plane

---

## What You Will Master

- Envoy's four stages — listener, route, cluster, endpoint — and the subcommand that shows each.
- Reading an Istio cluster name: `direction|port|subset|fqdn`, and what an empty subset field means.
- Narrowing a query with `--fqdn`, `--port`, `--name` and `--cluster` instead of reading a full dump.
- Telling inbound configuration from outbound, and why server-side policy is only visible on the receiving proxy.
- Ports 15001 and 15006, and what `PassthroughCluster` means.
- Mapping a symptom onto a stage: `404` at the route, `503` at the cluster or the endpoint.
- Inspecting a proxy's certificates with `proxy-config secret`.
- Reading a `503` as a statement about the proxy, and the response flags `NC`, `UH`, `UF`, `UC` and `NR`.
- Deciding whether to fix the route or define the missing subset — and why the choice matters.
- How a Service port with no declared protocol produces the same `503` from a completely different cause.

---

## The Learning Path

### 1. Read The Proxy Configuration
*   **Module Reader:** **[Module 1: Read The Proxy Configuration](./module-01/course.md)**
    *   Deep dive, in order:
        1. [Capture And Listeners](./module-01/course-01-capture-and-listeners.md)
        2. [Routes](./module-01/course-02-routes.md)
        3. [Clusters And Endpoints](./module-01/course-03-clusters-and-endpoints.md)
        4. [The Inbound Direction, Certificates And Method](./module-01/course-04-inbound-secrets-and-method.md)
*   **Hands-on Playground:** `sections/section-040/module-01/playground` — a kind cluster with Istio installed and namespace `proxycfg-demo`, with working routing in place so every stage has real configuration to read.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/module-01/playground
    ```
*   **Graded Lab:** **[Build The Routing, Then Prove It From The Proxy](./module-01/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/module-01/labs/lab-01
    ```

### 2. Debug A 503 Caused By A Missing Subset
*   **Module Reader:** **[Module 2: Debug A 503 Caused By A Missing Subset](./module-02/course.md)**
    *   Deep dive, in order:
        1. [Who Answered With 503](./module-02/course-01-who-answered-with-503.md)
        2. [Walking The Chain](./module-02/course-02-walking-the-chain.md)
        3. [Choosing The Fix, And The Other Cause](./module-02/course-03-choosing-the-fix.md)
*   **Hands-on Playground:** `sections/section-040/module-02/playground` — a kind cluster with Istio installed and namespace `fivezerothree-demo`, where a `VirtualService` routes to a subset no `DestinationRule` defines and every request fails.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/module-02/playground
    ```
*   **Graded Lab:** **[Trace A 503 To Its Exact Stage](./module-02/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/module-02/labs/lab-01
    ```

Each playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished — the name is printed in each module's playground callout.

---

## Section Capstone

**[Two 503s, Two Different Stages](./capstone/labs/lab-01/question.md)** — one graded scenario
combining this section's modules, with several independent faults to find and
fix. Work it after the module labs.

> `dpcapstone-demo` runs two services and neither behaves. Both destination pods are `2/2 Running` with no restarts.

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/capstone/labs/lab-01
astrona submit
```
