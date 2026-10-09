# Section 050: Debugging Data Plane Request Failures

Astronaut, every communications officer in the mesh (the sidecar proxy on every ship) keeps a flight log: the **access log**, one line per signal. `istioctl proxy-config` tells you what a proxy is configured to do. The access log tells you what it actually did, and a short code near the front of each line, the **response flag**, names the reason the request ended the way it did.

The first module teaches that line: how to switch logging on, how to read the fields that matter, and what each flag points at. The second module uses it on the failure that is hardest to spot any other way: a mutual TLS (mTLS) mismatch. Two valid objects, written by two different people, disagree about whether a connection should be encrypted. The evidence is as much in what is *missing* from one log as in what is written in the other.

**Curriculum item covered:** Troubleshooting the Mesh Data Plane

## What you will master

- Switching on access logging for the whole mesh with `meshConfig.accessLogFile`, or for one namespace with a `Telemetry` object.
- Finding the response flag, the upstream host and the cluster in a default-format log line.
- `UH`, `NC`, `UF`, `UC`, `UO`, `UT`, `NR`, `DC`, and what a bare `-` tells you.
- Telling from a pair of logs whether a request ever reached its destination.
- Producing a timeout, a circuit breaker rejection, a routing miss and an authorization denial on purpose.
- Why an `AuthorizationPolicy` denial is only explained on the destination proxy, in the response code details.
- The two objects that set up mTLS (`PeerAuthentication` for the server, `DestinationRule` for the client) and which combinations fail.
- The signature of `UF` on the client with nothing on the server, and why the destination logs nothing.
- Why no `DestinationRule` at all is the safe default for traffic inside the mesh.
- Proving traffic is encrypted, not just working, with `connection_security_policy`.

## The learning path

Work the modules in order. Each module has a playground to keep open while you read, and a graded mission right after the part that teaches its skill.

### 1. Read Envoy Access Logs And Response Flags

**[Read Envoy Access Logs And Response Flags](./module-01/course.md)**, in the namespace `accesslog-demo`, with access logging on and nothing broken until you break it yourself:

1. [Turning Logging On, And Scoping It](./module-01/course-01-enabling-and-scoping-logs.md)
2. [The Anatomy Of A Line](./module-01/course-02-anatomy-of-a-log-line.md)
3. [Flags, And Which Proxy Wrote The Line](./module-01/course-03-flags-and-which-proxy.md)
4. [Failures The Client's Proxy Decides](./module-01/course-04-failures-the-client-proxy-decides.md), then the mission **[Scope The Logs, Bound The Latency, Name The Flag](./module-01/labs/lab-01/question.md)**
5. [A Denial On The Other Proxy](./module-01/course-05-a-denial-on-the-other-proxy.md)
6. [Wrap-Up: Mission Debrief](./module-01/course-06-wrap-up.md)

### 2. Debug A 503 Caused By An mTLS Mismatch

**[Debug A 503 Caused By An mTLS Mismatch](./module-02/course.md)**, in the namespace `mtlsfail-demo`, where a `STRICT` `PeerAuthentication` and a `DestinationRule` that switches off client TLS already make every request fail:

1. [Two Objects, Two Ends Of One Connection](./module-02/course-01-two-objects-two-ends.md)
2. [The Signature](./module-02/course-02-the-signature.md)
3. [Fixing It, And Proving Encryption](./module-02/course-03-fixing-and-proving-encryption.md), then the mission **[A 503 Where The Destination Log Is Empty](./module-02/labs/lab-01/question.md)**
4. [Wrap-Up: Mission Debrief](./module-02/course-04-wrap-up.md)

Each playground is ungraded: it starts, prepares the environment, and waits. There is no task and no `astrona submit`. The landing page of each module launches it, and its wrap-up page shows how to remove it.

## Section capstone

**[Diagnose Two Failures From The Logs Alone](./capstone/labs/lab-01/question.md)** is one graded scenario that combines both modules. Nothing in `logcapstone-demo` works: an mTLS mismatch hides an authorization denial, and you can only see the second fault after you fix the first. Work it after the module missions.

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
