# Section 050: Debugging Data Plane Request Failures

Every sidecar proxy in the mesh can write an **access log**: one line per request that passes through it. The sidecar proxy (Envoy) is the container Istio adds to each pod, and all inbound and outbound traffic of the pod goes through it. `istioctl proxy-config` tells you what a proxy is configured to do. The access log tells you what it actually did, and a short code near the front of each line, the **response flag**, names the reason a request ended the way it did.

The first module teaches that line: how to switch logging on, how to read the fields that matter, what each flag points at, and which proxy decided a failure. The second module uses it on the failure that is hardest to spot any other way: a mutual TLS (mTLS) mismatch. Two valid objects, often written by two different people, disagree about whether a connection should be encrypted. The evidence is as much in what is *missing* from one log as in what is written in the other.

**Curriculum item covered:** Troubleshooting the Mesh Data Plane

## What you will learn

- Switching on access logging for the whole mesh with `meshConfig.accessLogFile`, or for one namespace with a `Telemetry` object.
- Finding the response flag, the upstream host and the upstream cluster in a line in the default format.
- What `UH`, `NC`, `UF`, `UC`, `UO`, `UT`, `NR` and `DC` mean, and what a bare `-` tells you.
- Telling from a pair of logs whether a request ever reached its destination.
- Producing a timeout, a circuit breaker rejection, a routing miss and an authorization denial on purpose.
- Why an `AuthorizationPolicy` denial is only explained on the destination's proxy, in the response code details.
- The two objects that set up mTLS (`PeerAuthentication` for the server, `DestinationRule` for the client) and which combinations fail.
- The signature of `UC` on the client's proxy with `filter_chain_not_found` on the destination's proxy, and why the destination logs no request.
- Why no `DestinationRule` at all is the safe default for traffic inside the mesh.
- Proving traffic is encrypted, not only working, with `connection_security_policy`.

## The learning path

Work through the modules in order. Each module has a landing page, a few short parts, a graded lab right after each part it tests, and a summary. Each module also has its own playground, a cluster where you can explore freely, and its landing page starts it for you.

### 1. Read Envoy Access Logs And Response Flags

The module works in the namespace `accesslog-demo`, with access logging on and nothing broken until you break it yourself. Its parts, in order:

1. Turning Logging On, And Scoping It
2. The Anatomy Of A Line
3. Flags, And Which Proxy Wrote The Line
4. Failures The Client's Proxy Decides, followed by the lab **Scope The Logs, Bound The Latency, Name The Flag**
5. A Denial On The Other Proxy, followed by the lab **Find Which Proxy Refused The Request**
6. Summary

### 2. Debug A 503 Caused By An mTLS Mismatch

The module works in the namespace `mtlsfail-demo`, where a `STRICT` `PeerAuthentication` and a `DestinationRule` that switches off client TLS already make every request fail. Its parts, in order:

1. Two Objects, Two Ends Of One Connection
2. The Signature
3. Fixing It, And Proving Encryption, followed by the lab **A 503 Where The Destination Log Is Empty**
4. Summary

Each playground is ungraded: it starts, prepares the environment, and waits. There is no task and no `astrona submit`.

## Section capstone

The capstone, **Diagnose Two Failures From The Logs Alone**, is one graded scenario that combines both modules. Nothing in `logcapstone-demo` works: an mTLS mismatch hides an authorization denial, and you can only see the second fault after you fix the first. Work it after the module labs.

Start the capstone:

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/capstone/labs/lab-01
```

When you think you are done, send it for grading:

```bash
astrona submit -c sections/section-050/capstone/labs/lab-01
```

When you are finished, remove it:

```bash
astrona destroy ats-016-capstone-050
```
