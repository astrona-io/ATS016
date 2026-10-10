# Summary

Every sidecar proxy in the mesh can write an access log with one line per request. This module showed how to switch that log on, how to read a line, and how the response flag and the proxy that wrote the line together point at the cause of a failure.

## What you learned

The access log is switched on for the whole mesh with `meshConfig.accessLogFile: /dev/stdout`, or for a smaller scope with a `Telemetry` object. A `Telemetry` object in the root namespace covers the mesh, one in an application namespace covers that namespace, and one with a `selector` covers matching workloads. The narrowest scope wins, `disabled: true` switches off one busy workload, and a CEL filter such as `response.code >= 400` keeps only some lines. The lines are container output, read with `kubectl logs <pod> -c istio-proxy`, and they disappear with the pod.

A line in the default format has about twenty fields without labels. Six of them carry the diagnosis: the status and the response flag, the response code details, the duration against the upstream service time, the authority, the upstream host, and the upstream cluster. `via_upstream` in the details means the application answered. An upstream host of `-` means the proxy never made a connection. The request id is the same on both proxies' lines, so you can find one request on both sides.

The flags form a model. `U` flags are about the upstream, `D` flags about the client, and `N` flags mean the proxy could not decide where to go. From `NR` and `NC` through `UH`, `UO` and `UF` to `UC` and `UT`, each flag marks how far the request got. Each proxy writes its access log in short batches, so wait a moment after a request before you read its line. A `-` with an error status points at the application, not at Istio. The upstream cluster shows which proxy wrote a line: `outbound|…` on the client and `inbound|…` on the destination.

The client's proxy decides timeouts, circuit breaker rejections and routing misses, while the destination's proxy decides authorization. The key facts to remember are these:

- `UT` comes with `504` and a duration close to the route timeout; a fault delay on the same rule never triggers it, because the fault filter runs before the router.
- `UO` comes with `503`, a duration of `0` and no upstream host: your own `connectionPool` limits rejected the request.
- `NR` comes with `404` and no upstream host: no route matched the request.
- An authorization denial shows `403` with the flag `-` on both sides, and only the destination's response code details name the policy: `rbac_access_denied_matched_policy[...]`.
- A count of flags over a window of traffic shows which failure is most common.

<!-- astrona:playground:destroy -->
