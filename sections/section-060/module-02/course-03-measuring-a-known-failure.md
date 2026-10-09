# Measuring A Known Failure

A query you cannot check is a query you cannot trust. Fault injection is a training drill: you tell the mesh to fail signals on purpose. It gives a **known** answer, here 30% errors and a 500ms delay, so you can check the measurement against the thing you measured. This part does exactly that, and then reads the difference between the client's and the server's view that the drill creates.

## Get ready to measure

You need two things in place: a query helper and steady traffic.

<!-- astrona:playground:renew -->

Define the helper. `prom_query` sends its first argument to Prometheus from the `tester` pod:

```sh
prom_query() { kubectl -n metrics-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' --data-urlencode "query=$1"; echo; }
```

Start the load loop in the background inside the `tester` pod, about ten requests a second. If it is already running, skip this step, so you do not run it twice:

```sh
kubectl -n metrics-demo exec deploy/tester -- sh -c \
  'nohup sh -c "while true; do curl -s -o /dev/null -X POST http://notification-service/notify; sleep 0.1; done" >/dev/null 2>&1 &'
```

## Injecting a known failure

This `VirtualService` (the flight plan for the beacon) runs a drill on two kinds of request at once. It makes the caller's proxy answer 30% of requests with a `500`, and hold back 50% of requests for 500 milliseconds before sending them on.

### Add 30% errors and a 500ms delay on half the requests

Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: metrics-demo
spec:
  hosts:
    - notification-service
  http:
    - fault:
        abort:
          httpStatus: 500
          percentage:
            value: 30
        delay:
          fixedDelay: 500ms
          percentage:
            value: 50
      route:
        - destination:
            host: notification-service
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

Then check the result. Wait 90 seconds, and measure the error ratio from the client's side:

```sh
sleep 90
prom_query 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) / sum(rate(istio_requests_total{reporter="source"}[1m]))'
```

You should see something like:

```text
{"status":"success","data":{"resultType":"vector","result":[
  {"metric":{},"value":[1774000000,"0.29"]}]}}
```

The answer is roughly `0.3`: the injected percentage, **measured**, not assumed. Two details make this a real check and not luck. The `sleep 90` matters: a `[1m]` window that still holds samples from before the fault gives a lower number, and reading too early is the most common way to doubt a correct query. And `reporter="source"` matters even more: the caller's proxy injects the abort, so this ratio only exists on the caller's side.

## The asymmetry, and what it proves

Now ask the same question without fixing the reporter. The two views split apart.

### See the same fault from both sides

Group the rate by reporter and response code:

```sh
prom_query 'sum(rate(istio_requests_total{destination_workload="notification-service-v1"}[1m])) by (reporter, response_code)'
```

You should see something like:

```text
  {"metric":{"reporter":"destination","response_code":"200"},"value":[...,"6.9"]},
  {"metric":{"reporter":"source","response_code":"200"},"value":[...,"6.9"]},
  {"metric":{"reporter":"source","response_code":"500"},"value":[...,"2.9"]}
```

There are three series, and **the missing fourth is the finding**. There is no `reporter="destination"` line for `500`. The server never received those requests, because the client's own proxy, the tester ship's communications officer, stopped them.

Read the rates as well. `6.9` succeeded on both sides, and `2.9` failed on the client only. Together they make up the roughly 9.8 requests a second the loop sends. The numbers confirm that the `500`s were taken away from what reached the destination, not added to it.

In a real incident, this asymmetry is your evidence that the failure lives in the client's proxy or on the path between the two, **not** in the service everyone blames. As a rule:

| Pattern | Conclusion |
| --- | --- |
| errors in `source` only | the request never arrived — client-side configuration, connectivity, or the client's own limits |
| errors in both | it arrived and failed there — destination policy or the application |
| errors in `destination` only | rare; the response path, or a caller outside the mesh you are not seeing |

### Name the cause with the response flag

Group the client-side errors by `response_flags` to name the cause outright. A response flag is the short code the communications officer stamps on a failed signal in the flight log:

```sh
prom_query 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) by (response_flags)'
```

The result names the flag the client proxy wrote for these aborted requests, the same code you would find in its access log.

## Latency lives in a different metric

The delay half of the drill does not show in the counters at all. A delayed request that succeeds is still a `200`. It shows in the duration histogram, which is why "is it slow, or is it failing" takes two queries, not one.

### Measure the delay with percentiles

Ask for the 99th and the 50th percentile of request duration, from the client's side:

```sh
prom_query 'histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{destination_workload="notification-service-v1",reporter="source"}[1m])) by (le))'
prom_query 'histogram_quantile(0.50, sum(rate(istio_request_duration_milliseconds_bucket{destination_workload="notification-service-v1",reporter="source"}[1m])) by (le))'
```

You should see something like:

```text
  {"metric":{},"value":[1774000000,"650"]}
  {"metric":{},"value":[1774000000,"480"]}
```

That is several hundred milliseconds, for an app that answers in under one: the injected 500ms, visible in the slow end. The median (the 50th percentile) is the more interesting number. The delay hits **50%** of requests, so the median sits right on the line between delayed and undelayed traffic. That is exactly what a half-and-half split should produce.

Neither figure is exact. A histogram percentile is an estimate between bucket edges, so read these as "about half a second". Comparing the 50th with the 99th percentile is the practical technique: close together means everything is slow, far apart means a slow tail that hits only some requests.

Leave the drill and the load loop in place if you go straight on to the dashboards and the clean-up. Otherwise, remove them now with `kubectl -n metrics-demo delete virtualservice notification` and `kubectl -n metrics-demo exec deploy/tester -- pkill -f 'while true' || true`.

## Common pitfalls

> [!WARNING]
> - **Reading a rate before the window has cleared.** A `[1m]` window that still holds samples from before the change gives a watered-down answer. Wait a full window.
> - **Querying the wrong reporter for a client-side fault.** Injected aborts, circuit breakers and timeouts never reach the destination's counters.
> - **Looking for latency in the response code counters.** A delayed success is still a `200`. Only the histogram shows it.
> - **Treating a percentile as exact.** It is an estimate. Compare the 50th and 99th percentiles instead of trusting a single figure.
> - **Starting the load loop twice.** Two loops double the rate and make every number harder to check.

> *A drill with a known answer is the only honest test of a query, and the reporter label shows which ship saw the failure.*
