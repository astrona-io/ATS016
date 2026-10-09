# Section 040: Reading Data Plane Configuration

Astronaut, sometimes a signal still does the wrong thing after every outside check has passed. The configuration is coherent, mission control (`istiod`) delivered it, and the spaceship (pod) has its communications officer (the sidecar proxy) on board. There is nowhere left to look except inside the officer's own orders book: the Envoy configuration.

That is less daunting than it sounds. Envoy handles a request in four stages, always in the same order: listener, route, cluster, endpoint. `istioctl proxy-config` has one subcommand for each stage. The first module walks all four on a working proxy, because you cannot recognise a wrong configuration until you know what a right one looks like. The second module uses the same chain on the most common failure in the mesh: a `503` from a route that points at a destination that does not exist.

**Curriculum item covered:** Troubleshooting the Mesh Data Plane

## What you will master

- Envoy's four stages (listener, route, cluster, endpoint) and the `istioctl proxy-config` subcommand that shows each.
- Reading an Istio cluster name, `direction|port|subset|fqdn`, and what an empty subset field means.
- Narrowing a query with `--fqdn`, `--port`, `--name` and `--cluster` instead of reading a full dump.
- Telling inbound configuration from outbound, and why server-side policy is only visible on the receiving proxy.
- Ports 15001 and 15006, and what `PassthroughCluster` means.
- Mapping a symptom onto a stage: `404` at the route, `503` at the cluster or the endpoint.
- Reading a proxy's certificates with `proxy-config secret`.
- Reading a `503` as a statement about the proxy, with the response flags `NC`, `UH`, `UF`, `UC` and `NR`.
- Deciding whether to fix the route or define the missing subset, and why the choice matters.
- How a Service port with no declared protocol produces the same `503` from a completely different cause.

## The learning path

Work through the modules in order. Each module has a playground you keep open while reading, and a graded mission right after the part that teaches its skill.

### 1. Read The Proxy Configuration

Start at the landing page, **[Read The Proxy Configuration](./module-01/course.md)**. Its playground runs the planet (namespace) `proxycfg-demo` with working routing in place, so every stage has real configuration to read.

1. [Capture And Listeners](./module-01/course-01-capture-and-listeners.md)
2. [Routes](./module-01/course-02-routes.md)
3. [Clusters And Endpoints](./module-01/course-03-clusters-and-endpoints.md)
4. [The Receiving Proxy And Its Certificates](./module-01/course-04-the-receiving-proxy-and-certificates.md)
5. [The Four-Stage Walk](./module-01/course-05-the-four-stage-walk.md), followed by the mission **[Build The Routing, Then Prove It From The Proxy](./module-01/labs/lab-01/question.md)**
6. [Wrap-Up: Mission Debrief](./module-01/course-06-wrap-up.md)

### 2. Debug A 503 Caused By A Missing Subset

Start at the landing page, **[Debug A 503 Caused By A Missing Subset](./module-02/course.md)**. Its playground runs the planet `fivezerothree-demo`, where a `VirtualService` routes to a subset no `DestinationRule` defines and every request fails.

1. [Who Answered With 503](./module-02/course-01-who-answered-with-503.md)
2. [Walking The Chain](./module-02/course-02-walking-the-chain.md)
3. [Choosing And Proving The Fix](./module-02/course-03-choosing-and-proving-the-fix.md), followed by the mission **[Trace A 503 To Its Exact Stage](./module-02/labs/lab-01/question.md)**
4. [The Other Cause: An Undeclared Port](./module-02/course-04-the-other-cause-an-undeclared-port.md)
5. [Wrap-Up: Mission Debrief](./module-02/course-05-wrap-up.md)

Each playground is ungraded: it starts, prepares the environment, and waits. There is no task and no `astrona submit`. Each module's landing page starts it, and its wrap-up page shows how to remove it.

## Section capstone

**[Two 503s, Two Different Stages](./capstone/labs/lab-01/question.md)** is one graded scenario that combines both modules. The planet `dpcapstone-demo` runs two services, and neither behaves, for two different reasons at two different stages. Work it after the module missions.

Start it:

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/capstone/labs/lab-01
```

Send it for grading when you are done:

```bash
astrona submit -c sections/section-040/capstone/labs/lab-01
```

Then remove it:

```bash
astrona destroy ats-016-capstone-040
```
