# Overview: Read Envoy Access Logs And Response Flags (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the starting workloads, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy ats-016-playground-050-01`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH. The `demo` profile switches on access logging for the whole mesh: every sidecar proxy writes one line per request to its standard output.
- Namespace **`accesslog-demo`**, labelled `istio-injection=enabled`. Every pod has an `istio-proxy` sidecar proxy (Envoy), which handles all inbound and outbound traffic of the pod.

  | Kubernetes name | What it is |
  | --- | --- |
  | `notification-service` | Service on port `80` |
  | `notification-service-v1` | Deployment with nginx, which answers `["EMAIL"]` on any path. A request for `/slow` is forwarded to an HTTP server in the same pod that waits five seconds before it answers |
  | `tester` | Client pod with `curl`; send test requests from here |
  | `access-logs` | A `Telemetry` object that switches on the `envoy` access log provider for this namespace |

- **No `VirtualService`, `DestinationRule` or `AuthorizationPolicy`.** Traffic starts healthy, and every failure here is one you apply yourself.

## Helpers

Paste these once in each new terminal. `send_request` sends one `POST` to the path you name (default `/notify`) from the `tester` pod and prints the status code. `client_log` and `destination_log` print the newest access log lines of the `tester` pod's proxy and of the destination's proxy; the argument is the number of lines and defaults to `1`. `count_flags` counts the response flags in the `tester` pod's last 100 access log lines. Each proxy writes its access log in short batches, and `send_request` waits two seconds after the request so the next log read shows it.

```sh
send_request() {
  kubectl -n accesslog-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' -X POST "http://notification-service${1:-/notify}"
  sleep 2
}
client_log() {
  kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail="${1:-1}"
}
destination_log() {
  kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy --tail="${1:-1}"
}
count_flags() {
  kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=100 \
    | grep '^\[' | awk '{print $6}' | sort | uniq -c | sort -rn
}
```

Use them like this: `send_request /slow`, `client_log 3`, `destination_log`, `count_flags`.

## Practice tasks

- Send one request and read `client_log` and `destination_log`. Work out from the upstream cluster field which proxy wrote each line.
- Put a `VirtualService` with `timeout: 1s` on `notification-service`, run `send_request /slow`, and predict the status, the flag and the duration before you read `client_log`. Then read `destination_log` and find the flag the destination's proxy wrote.
- Add a `fault.delay` of `5s` to the same route rule as the timeout and send the request again. Explain why the flag is now `DI` and not `UT`.
- Apply a `DestinationRule` with a connection pool of one, send thirty requests at the same time, and use `count_flags` to see how many were rejected.
- Scale `notification-service-v1` to zero replicas, send a request, and name the flag before you read the log. Scale it back to one.
- Add a `filter` with the expression `response.code >= 400` to the `access-logs` `Telemetry` object, then send both successful and failing requests and compare what is logged.
- Apply a `DENY` `AuthorizationPolicy` that matches only the `GET` method, then send a `GET` and a `POST` and find the policy name in `destination_log`.
