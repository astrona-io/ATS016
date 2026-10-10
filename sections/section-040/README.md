# Section 040: Reading Data Plane Configuration

Sometimes a request still does the wrong thing after every outside check has passed. The configuration is coherent, `istiod` (Istio's control plane) has sent it, and the pod has its sidecar proxy, the Envoy container Istio adds to each pod. There is nowhere left to look except the configuration inside that proxy.

That is less work than it sounds. Envoy handles a request in four stages, always in the same order: listener, route, cluster, endpoint. `istioctl proxy-config` has one subcommand for each stage. The first module walks all four on a working proxy, because you cannot recognise a wrong configuration until you know what a correct one looks like. The second module uses the same chain on two common failures: a `503` from a route that names a destination that does not exist, and routing rules that are ignored because a Service port is declared as TCP.

**Curriculum item covered:** Troubleshooting the Mesh Data Plane

## What you will learn

- Envoy's four stages (listener, route, cluster, endpoint) and the `istioctl proxy-config` subcommand that shows each.
- Reading an Istio cluster name, `direction|port|subset|fqdn`, and what an empty subset field means.
- Narrowing a query with `--fqdn`, `--port`, `--name` and `--cluster` instead of reading a full dump.
- Telling inbound configuration from outbound, and why server-side policy is only visible on the receiving proxy.
- Ports 15001 and 15006, and what `PassthroughCluster` means.
- Mapping a symptom to a stage: `404` at the route, `503` at the cluster or the endpoints.
- Reading a proxy's certificates with `proxy-config secret`.
- Reading a `503` as a statement about the proxy, with the response flags `NC`, `UH`, `UF`, `UC` and `NR`.
- Deciding whether to fix the route or define the missing subset, and why the choice matters.
- How Istio decides a Service port's protocol, and why a port declared as TCP makes every HTTP rule for it do nothing.

## The learning path

Work through the modules in order. Each module has a landing page that starts its playground, a few short parts, a graded lab right after the part it tests, and a summary. A playground is ungraded: it starts, prepares the environment, and waits. There is no task and no `astrona submit`.

### 1. Read The Proxy Configuration

The playground runs the namespace `proxycfg-demo` with working routing in place, so every stage has real configuration to read.

1. Capture And Listeners
2. Routes
3. Clusters And Endpoints
4. The Receiving Proxy And Its Certificates
5. The Four-Stage Walk, followed by the lab **Build The Routing, Then Prove It From The Proxy**
6. Summary

### 2. Debug A 503 Caused By A Missing Subset

The playground runs the namespace `fivezerothree-demo`, where a `VirtualService` routes to a subset no `DestinationRule` defines and every request fails.

1. Who Answered With 503
2. Walking The Chain
3. Choosing And Proving The Fix, followed by the lab **Trace A 503 To Its Exact Stage**
4. Declaring The Port Protocol, followed by the lab **Declare The Service Port Protocol So The Route Applies**
5. Summary

## Section capstone

**Two 503s, Two Different Stages** is one graded scenario that combines both modules. The namespace `dpcapstone-demo` runs two services, and neither behaves, for two different reasons at two different stages. Work it after the module labs.

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
