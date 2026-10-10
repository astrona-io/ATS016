# Overview: Debug A 503 Caused By An mTLS Mismatch (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the starting workloads, applies a broken mutual TLS (mTLS) configuration, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy ats-016-playground-050-02`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. Access logging is on for the whole mesh, which this playground depends on.
- Namespace **`mtlsfail-demo`**, labelled `istio-injection=enabled`. Every pod has an `istio-proxy` sidecar proxy (Envoy), which handles all inbound and outbound traffic of the pod.

  | Kubernetes name | What it is |
  | --- | --- |
  | `notification-service` | Service on port `80` |
  | `notification-service-v1` | Deployment with nginx, which answers `["EMAIL"]` on any path |
  | `tester` | Client pod with `curl`; send test requests from here |

- **A live mTLS mismatch.** A `PeerAuthentication` named `default` sets the whole namespace to `STRICT`, so the server side accepts only mTLS. A `DestinationRule` named `notification` sets `trafficPolicy.tls.mode: DISABLE`, so the client side sends plain text. Every request returns `503`.

## Helpers

Paste these once in each new terminal. `send_request` sends one `POST` to `notification-service` from the `tester` pod and prints the status code. `both_logs` prints the newest access log lines of the client's proxy and of the destination's proxy. `security_policy` counts the `connection_security_policy` values the destination's proxy reports in `istio_requests_total`.

```sh
send_request() {
  kubectl -n mtlsfail-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
}
both_logs() {
  echo '--- client ---'
  kubectl -n mtlsfail-demo logs deploy/tester -c istio-proxy --tail=3
  echo '--- destination ---'
  kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
}
security_policy() {
  kubectl -n mtlsfail-demo exec deploy/notification-service-v1 -c istio-proxy -- \
    pilot-agent request GET stats/prometheus \
    | grep istio_requests_total | grep -o 'connection_security_policy="[^"]*"' | sort | uniq -c
}
```

Use them like this: `send_request`, `both_logs`, `security_policy`.

## Practice tasks

- Run `send_request`, wait two seconds, and run `both_logs` before you change anything. Confirm that the destination's proxy wrote only a `filter_chain_not_found` line and no request line. Explain why from the flag and the upstream host on the client's line.
- Fix it from the wrong end: set the `PeerAuthentication` to `PERMISSIVE` and leave the `DestinationRule` alone. Run `send_request` and `security_policy`, and explain why the traffic works but is not encrypted. Set it back to `STRICT`.
- Delete the `DestinationRule` completely and confirm with `security_policy` that the traffic still uses mTLS.
- Reverse the mismatch: set the `PeerAuthentication` to `DISABLE` and the client to `tls.mode: ISTIO_MUTUAL`. Compare the flags and both logs with the original failure.
- Create a namespace without sidecar injection, start a `curl` pod in it, and call `notification-service.mtlsfail-demo` while the server is `STRICT`. Compare the signature and decide which fix is correct.
- Set the client to `tls.mode: MUTUAL` without any certificates and read how that failure differs.
