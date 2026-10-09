# Solution: Scope The Logs, Bound The Latency, Name The Flag

The grader checks three things: a `Telemetry` object in `accesslog-demo` switches on the `envoy` provider, the `VirtualService` for `notification-service` has `timeout: 2s`, and the tester's proxy log contains a `UT` flag. This walkthrough builds each one and proves it.

## Step 1: See the current behaviour

Time one request from the `tester` ship to the `notification-service` beacon:

```sh
time kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

```text
200
real    0m5.2s
```

A `200` after about five seconds. Nothing is failing, and that is the point: a wait with no limit is the caller's problem, not the server's.

Look at the flight plan (the `VirtualService`) that already exists for the beacon:

```sh
kubectl -n accesslog-demo get virtualservice
```

There is one, called `notification`. It has no `timeout`.

## Step 2: Declare logging for this namespace

Switching logging on for the whole mesh is an install setting. A `Telemetry` object is the flight log settings for one planet: a Kubernetes object in the namespace that you can apply, scope and delete without touching the install.

Save this as `telemetry-access-logs.yaml`:

```yaml
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-logs
  namespace: accesslog-demo
spec:
  accessLogging:
    - providers:
        - name: envoy
```

Apply it:

```sh
kubectl apply -f telemetry-access-logs.yaml
```

Then check the result:

```sh
kubectl -n accesslog-demo get telemetry
```

`envoy` is the built-in provider name for the standard text access log. **Where the object lives** decides its scope: in an application namespace it covers that namespace; in the root namespace (`istio-system`) it covers the mesh; with a `selector` it covers matching workloads.

Submit to see the first check pass:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-01
```

## Step 3: Bound the wait with a timeout

Put `timeout: 2s` on the route. The dependency itself is slow, so the wait happens upstream, where the tester's proxy can cut it short with a route timeout.

The starting `notification` `VirtualService` also carries a 5-second `fault.delay`. Do not keep it next to the timeout: in Envoy, the fault filter runs before the router, and the router is what enforces the route timeout. A delay injected on the same rule happens before the timeout clock starts. The fixed flight plan has only the route and the timeout.

Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: accesslog-demo
spec:
  hosts:
    - notification-service
  http:
    - timeout: 2s
      route:
        - destination:
            host: notification-service
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

Then check the result:

```sh
kubectl -n accesslog-demo get virtualservice notification -o yaml | grep timeout
```

The output should show `timeout: 2s`.

## Step 4: Produce the flag and read it

Send one request and read the tester's newest flight log line:

```sh
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
```

The output looks like this (the log line is shortened):

```text
504
[...] "POST /notify HTTP/1.1" 504 UT response_timeout - "-" 0 24 2000 - ... "-" outbound|80||notification-service...
```

Three things to read on that line:

- **`504`**, not `503`: a timeout has its own status code.
- **`UT`**: upstream request timeout, the route timeout firing. The details field says `response_timeout`.
- **Duration about `2000`**: the *timeout*, not the five-second wait. The proxy gave up after two seconds.

Which proxy wrote it? The upstream cluster starts with `outbound|80||`, so this line comes from the tester's own sidecar, the sending side. The tester's proxy enforces the route timeout, so it is the one that stamped `UT` on the signal. Read the destination's side too:

```sh
kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

The destination's proxy does not decide the timeout. Whatever it logged, the `504` and the `UT` flag came from the sending ship.

Submit again. All three checks should now pass:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-01
```

## Step 5: Summarise the window

Count the flags in the tester's last 60 log lines:

```sh
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=60 \
  | awk '{print $5}' | sort | uniq -c | sort -rn
```

```text
  6 UT
 14 -
```

One line is a case; a count is a pattern. On a real incident this is the fastest way to see which failure is most common.

## Common mistakes

- Reading the application log instead of the proxy log. Failures the proxy makes never reach the application.
- Looking at only one side. Client and destination logs together tell you whether the request crossed the network.
- Assuming all `5xx` errors are the same. `UH`, `UF`, `UC`, `UO` and `UT` have different fixes.
- Forgetting that access logs are off by default in some profiles. No log lines is not the same as no traffic.
- Switching logging on for the whole mesh during an incident and drowning in it.
- Putting the timeout on the same rule as a `fault.delay` and expecting it to cut the delay short.

## Practice variations

- Add `filter: { expression: "response.code >= 400" }` to the `Telemetry` object and confirm only failures are logged.
- Set a custom `accessLogFormat` that includes the upstream cluster name.
- Tighten a `connectionPool` until you can produce `UO`, and compare its duration field with the `UT` line above.
