# Section 050: Debugging Data Plane Request Failures

`istioctl proxy-config` tells you what a proxy is configured to do. The access log tells you what it actually did — one line per request, with a short code near the front naming the reason the request ended the way it did.

Module 1 teaches that line: how to turn logging on, how to read the fields that matter, and what each response flag points at. Module 2 applies it to the failure that is hardest to identify any other way — an mTLS mismatch, where two valid objects written by two different people disagree about whether a connection should be encrypted, and the evidence is as much in what is *missing* from one log as in what is present in the other.

**Curriculum item covered:** Troubleshooting the Mesh Data Plane

---

## What You Will Master

- Enabling access logging mesh-wide with `meshConfig.accessLogFile`, or per namespace with a `Telemetry` object.
- Locating the response flag, the upstream host and the cluster in a default-format log line.
- `UH`, `NC`, `UF`, `UC`, `UO`, `UT`, `NR`, `DC` — and what a bare `-` tells you.
- Determining from a pair of logs whether a request ever reached its destination.
- Reproducing a timeout, a circuit breaker rejection, a routing miss and an authorization denial on demand.
- Why an `AuthorizationPolicy` denial is only explained on the destination proxy, in `RESPONSE_CODE_DETAILS`.
- The two objects that configure mTLS — `PeerAuthentication` for the server, `DestinationRule` for the client — and which combinations fail.
- The `UF`-on-the-client, nothing-on-the-server signature, and why the destination logs nothing.
- Why no `DestinationRule` at all is the safe default for in-mesh traffic.
- Proving traffic is encrypted rather than merely working, with `connection_security_policy`.

---

## The Learning Path

### 1. Read Envoy Access Logs And Response Flags
*   **Module Reader:** **[Module 1: Read Envoy Access Logs And Response Flags](./module-01/course.md)**
    *   Deep dive, in order:
        1. [Turning Logging On, And Scoping It](./module-01/course-01-enabling-and-scoping-logs.md)
        2. [The Anatomy Of A Line](./module-01/course-02-anatomy-of-a-log-line.md)
        3. [Flags, And Which Proxy Wrote The Line](./module-01/course-03-flags-and-which-proxy.md)
        4. [Producing Each Failure On Demand](./module-01/course-04-producing-each-failure.md)
*   **Hands-on Playground:** `sections/section-050/module-01/playground` — a kind cluster with Istio installed, namespace `accesslog-demo`, access logging on, and four manifests that each produce a different failure on demand.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-01/playground
    ```
*   **Graded Lab:** **[Scope The Logs, Bound The Latency, Name The Flag](./module-01/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-01/labs/lab-01
    ```

### 2. Debug A 503 Caused By An mTLS Mismatch
*   **Module Reader:** **[Module 2: Debug A 503 Caused By An mTLS Mismatch](./module-02/course.md)**
    *   Deep dive, in order:
        1. [Two Objects, Two Ends Of One Connection](./module-02/course-01-two-objects-two-ends.md)
        2. [The Signature](./module-02/course-02-the-signature.md)
        3. [Fixing It, And Proving Encryption](./module-02/course-03-fixing-and-proving-encryption.md)
*   **Hands-on Playground:** `sections/section-050/module-02/playground` — a kind cluster with Istio installed and namespace `mtlsfail-demo`, holding a `STRICT` `PeerAuthentication` and a `DestinationRule` that disables client TLS. Every request fails on arrival.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-02/playground
    ```
*   **Graded Lab:** **[A 503 Where The Destination Log Is Empty](./module-02/labs/lab-01/question.md)** — exam-style task, graded on the final cluster state.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/module-02/labs/lab-01
    ```

Each playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished — the name is printed in each module's playground callout.

---

## Section Capstone

**[Diagnose Two Failures From The Logs Alone](./capstone/labs/lab-01/question.md)** — one graded scenario
combining this section's modules, with several independent faults to find and
fix. Work it after the module labs.

> Nothing in `logcapstone-demo` works. The intent, per the team's documentation, is:

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-050/capstone/labs/lab-01
astrona submit
```
