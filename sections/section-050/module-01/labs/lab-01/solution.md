# Solution: Scope The Logs, Bound The Latency, Name The Flag

## Step 1 — See the current behaviour

```sh
time kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

```text
200
real    0m5.2s
```

A `200` after five seconds. Nothing is failing — which is the point. Latency
without a bound is a caller's problem, not a server's.

## Step 2 — Declare logging for this namespace

Mesh-wide logging is an install setting; a `Telemetry` object is a namespaced
Kubernetes object you can apply, scope and delete without touching the install:

```sh
kubectl apply -f - <<'EOF'
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-logs
  namespace: accesslog-demo
spec:
  accessLogging:
    - providers:
        - name: envoy
EOF
```

`envoy` is the built-in provider name for the standard text access log. Scope is
decided by **where the object lives**: in an application namespace it covers
that namespace; in the root namespace it covers the mesh; with a `selector` it
covers one workload.

```sh
astrona submit
```

## Step 3 — Bound the delay with a timeout

Add `timeout` to the existing route. Keep the fault — the task is to bound the
slow dependency, not to delete the simulation of it:

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: accesslog-demo
spec:
  hosts:
    - notification-service
  http:
    - fault:
        delay:
          fixedDelay: 5s
          percentage:
            value: 100
      timeout: 2s
      route:
        - destination:
            host: notification-service
EOF
```

## Step 4 — Produce the flag and read it

```sh
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
```

```text
504
[...] "POST /notify HTTP/1.1" 504 UT response_timeout - "-" 0 24 2000 - ... "-" outbound|80||notification-service...
```

Four things to read on that line:

- **`504`**, not `503` — a timeout has its own status code.
- **`UT`** — upstream request timeout, the route timeout firing.
- **duration ≈ `2000`** — the *timeout*, not the five-second delay. The proxy
  gave up at two seconds.
- **upstream host `-`** — nothing was ever contacted.

Now check the destination:

```sh
kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

Nothing corresponding. The delay is injected by the **client's** proxy, before
the request is sent, so the destination never saw it. That pairing — a failure
on one side and silence on the other — is what tells you the request never
crossed the network.

```sh
astrona submit
```

## Step 5 — Summarise the window

```sh
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=60 \
  | awk '{print $5}' | sort | uniq -c | sort -rn
```

```text
  6 UT
 14 -
```

One line is a case; a tally is a pattern. On a real incident this is the fastest
way to see which failure dominates.

## Common mistakes

- Reading the application log instead of the proxy log. Proxy-generated failures
  never reach the application.
- Looking at only one side. Client and destination logs together tell you
  whether the request crossed the network.
- Assuming all `5xx` are the same. `UH`, `UF`, `UC`, `UO` and `UT` have
  different fixes.
- Forgetting that access logs are off by default in some profiles. No log lines
  is not the same as no traffic.
- Enabling logging mesh-wide during an incident and drowning in it.

## Practice variations

- Add `filter: { expression: "response.code >= 400" }` to the `Telemetry` object
  and confirm only failures are logged.
- Set a custom `accessLogFormat` that includes the upstream cluster name.
- Tighten a `connectionPool` until you can produce `UO`, and compare its
  duration field with the `UT` line above.
