# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the communications officer's orders book: what the sidecar proxy is configured to do, read one stage at a time with `istioctl proxy-config`.

**From [Capture And Listeners](./course-01-capture-and-listeners.md):**

- `iptables` rules inside the pod send outgoing signals to port `15001` and incoming signals to port `15006`, without the app knowing.
- A listener is the radio channel the proxy listens on. Its `DESTINATION` column says what comes next: a `Route:`, a `Cluster:` or `PassthroughCluster`.
- A port with no declared protocol may fall to the passthrough chain, and then no routing rule applies to it.

**From [Routes](./course-02-routes.md):**

- A route configuration is named after the port (`Route: 80`) and holds one virtual host per destination, chosen by the `Host` header.
- An empty `VIRTUAL SERVICE` column means no `VirtualService` applies to that host.
- The table's `MATCH` column shows only the path; header matches are only visible in `-o json`.

**From [Clusters And Endpoints](./course-03-clusters-and-endpoints.md):**

- A cluster name has four fields: `direction|port|subset|fqdn`. A subset cluster exists only if a `DestinationRule` defines that subset.
- Endpoints are pod IPs on the container port. `STATUS` is Kubernetes readiness; `OUTLIER CHECK` is this proxy's own verdict.
- A missing cluster (`NC`) and an empty cluster (`UH`) are different failures.

**From [The Receiving Proxy And Its Certificates](./course-04-the-receiving-proxy-and-certificates.md):**

- Client-side rules (`VirtualService`, `DestinationRule`) live on the sender; server-side policy (`PeerAuthentication`, `AuthorizationPolicy`) lives on the receiver's 15006 listener.
- The inbound cluster is named `inbound|<port>||` and has the type `ORIGINAL_DST`.
- `proxy-config secret` shows the workload certificate, valid for about a day, and the mesh root.

**From [The Four-Stage Walk](./course-05-the-four-stage-walk.md):**

- Walk listener, route, cluster, endpoint on the client, carrying each name to the next command; then check the destination.
- The response flag maps a symptom to a stage: `NR` to the route, `NC` to the cluster, `UH` to the endpoints.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Build The Routing, Then Prove It From The Proxy](./labs/lab-01/README.md) | The Four-Stage Walk | write subsets and a header route, then prove them from the proxy's route table and endpoints |

If you skipped it, go back to it now. It is short.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. Which port do an app's outgoing signals get redirected to, and which port do incoming signals get redirected to?</summary>

Outgoing signals go to port `15001`, incoming signals to port `15006`. The `iptables` rules inside the pod do the redirect, so the app needs no change.
</details>

<details>
<summary>2. The listener on port 80 hands off to <code>PassthroughCluster</code> only, with no <code>Route:</code>. What does that tell you?</summary>

The traffic is not treated as HTTP, so no route stage exists and no `VirtualService` can apply to it. Check how the Service port declares its protocol (its name or `appProtocol`).
</details>

<details>
<summary>3. The route table shows <code>/*</code> in the <code>MATCH</code> column for both rules. Does that mean neither rule has a header match?</summary>

No. The table shows only the path condition. Header, method and query conditions are only visible with `-o json`.
</details>

<details>
<summary>4. What do the four fields of <code>outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local</code> mean?</summary>

Direction (`outbound`), the Service port (`80`), the subset (`v1`), and the destination's fully qualified domain name. An empty third field would mean no subset.
</details>

<details>
<summary>5. The cluster's endpoints use port 8084, not 80. Is something wrong?</summary>

No. The sidecar connects straight to the pod on the container port. The Service port appears only in the cluster name.
</details>

<details>
<summary>6. An endpoint shows <code>HEALTHY</code> but <code>OUTLIER CHECK</code> is <code>FAILED</code>. What happened?</summary>

Kubernetes says the pod is ready, but this proxy has pushed the endpoint out after repeated errors. Other clients may still use it.
</details>

<details>
<summary>7. An <code>AuthorizationPolicy</code> seems not to apply. Which proxy's configuration do you read?</summary>

The destination's. Server-side policy lives in the filter chains of the receiving proxy's 15006 listener; it never appears in the caller's configuration.
</details>

<details>
<summary>8. How long is a workload certificate valid, and where do you see it?</summary>

About 24 hours. `istioctl proxy-config secret` shows it as `default`, with its `NOT BEFORE` and `NOT AFTER` times.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-040-01
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-016-lab-040-01
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *Listener, route, cluster, endpoint: read them in order, and the proxy tells you exactly where a signal went wrong.*
