# Grafana, Flight Logs And Proving The Fix

Measuring a failure is half the job, astronaut. The other half is finding the right screen fast, leaving evidence for the next person, and proving the fix worked with the same query that measured the problem. This part covers Grafana's bundled dashboards, access logs for one namespace, and the clean-up that proves the fault is gone.

## Grafana

Grafana is the set of dashboard screens in mission control. Its bundled Istio dashboards are the same PromQL queries you can write by hand, already written and laid out. Four come with the add-on, and knowing which one to open is most of the value:

| Dashboard | Scope | Open it for |
| --- | --- | --- |
| **Istio Mesh** | everything | the whole mesh at a glance: rate, success rate and latency per service. Where to start when you do not know which service is involved. |
| **Istio Service** | one Service | client and server views side by side, broken down by source workload — the `reporter` comparison, as panels. |
| **Istio Workload** | one workload | inbound **and outbound** traffic, so you can see what it calls as well as who calls it. |
| **Istio Control Plane** | `istiod` | push errors, rejected configuration, convergence time and memory of `istiod`, mission control itself. |

People forget the outbound half of the Workload dashboard. When a service is slow, its *outbound* panels answer "is it slow because something it calls is slow", without opening a second dashboard.

<!-- astrona:playground:renew -->

### Open Grafana

Forward Grafana's port from the cluster to your machine:

```sh
kubectl -n istio-system port-forward svc/grafana 3000:3000
```

Then open `http://localhost:3000` in a browser that can reach this machine. `istioctl dashboard grafana` does the same, and also tries to open a browser for you.

> [!TIP]
> When a Grafana panel shows something surprising, open its **Explore** view to see the PromQL behind it. Every panel is a query you could have written, and reading them is the fastest way to learn new `by (...)` groupings.

## Ask for the flight logs as well

Metrics answer "how much, how bad, since when". Access logs answer "what happened to *this* request". The access log is the ship's flight log: one line per signal, with the response flag in it. You want both.

A `Telemetry` object holds the flight log settings for one planet (namespace): which proxies keep a log, and with which provider. Istio's built-in provider for plain access logs is called `envoy`. Declaring it in a `Telemetry` object turns logging on for that namespace only, and you can take it back by deleting the object. You never touch the mesh-wide install.

Save this as `telemetry-access-logs.yaml`:

```yaml
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-logs
  namespace: metrics-demo
spec:
  accessLogging:
    - providers:
        - name: envoy
```

Apply it:

```sh
kubectl apply -f telemetry-access-logs.yaml
```

From now on, every sidecar in `metrics-demo` writes a line for each request to its `istio-proxy` container log, which you read with `kubectl logs ... -c istio-proxy`.

## Removing the fault and proving it

The steps below assume the fault drill is still applied: a `VirtualService` named `notification` in `metrics-demo` that aborts 30% of requests with a `500`. They also assume the background load loop is still running in the `tester` pod.

### Remove the fault

Leave the load loop running: a ratio needs traffic to measure. Delete the `VirtualService`:

```sh
kubectl -n metrics-demo delete virtualservice notification
```

You should see:

```text
virtualservice.networking.istio.io "notification" deleted
```

With no `VirtualService` left, the proxies use Istio's default routing for the Service, which is a valid, working setup.

### Prove it with the same query

Prove the fix with the query that measured the failure. Define the `prom_query` helper again if this is a new shell, wait for the one-minute window to slide past the fault, then measure the error ratio:

```sh
prom_query() { kubectl -n metrics-demo exec deploy/tester -- curl -s \
  'http://prometheus.istio-system:9090/api/v1/query' --data-urlencode "query=$1"; echo; }
sleep 70
prom_query 'sum(rate(istio_requests_total{reporter="source",response_code=~"5.."}[1m])) / sum(rate(istio_requests_total{reporter="source"}[1m]))'
```

You should see something like:

```text
{"metric":{},"value":[...,"0"]}
```

The error ratio falls back to zero as the window slides past the fault. **Counters keep their totals, and rates forget.** That one sentence is the whole difference between reading a raw metric and reading a query over it.

### Stop the load and send one last request

Stop the background loop, then send one request by hand:

```sh
kubectl -n metrics-demo exec deploy/tester -- pkill -f 'while true' || true
kubectl -n metrics-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

You should see:

```text
200
```

Traffic is healthy again, and the load generator is no longer running.

## The questions metrics answer

Every question below uses the same `sum(rate(...)) by (...)` shape with a different grouping:

| Question | Query shape |
| --- | --- |
| Is it broken, or was that one bad request? | error ratio |
| When did it start? | the same ratio, as a graph over a range |
| Who is affected? | `by (source_workload)` |
| Why is it failing? | `by (response_flags)` |
| Is it slow, or failing? | duration histogram against the code counter |
| Is the canary worse? | `by (destination_version)` |
| Is it encrypted? | `by (connection_security_policy)` |
| Which side sees the failure? | `by (reporter)` |

That is the practical takeaway: learn one query shape and a list of labels, not a list of queries.

## Common pitfalls

> [!WARNING]
> - **Forgetting to remove fault injection.** It keeps failing requests after you stop looking at the graph.
> - **Proving a fix too early.** A `[1m]` window still holds the failures for up to a minute. Wait a full window before you read the ratio.
> - **Turning on access logging for the whole mesh to debug one namespace.** A `Telemetry` object in the namespace is scoped and easy to undo.
> - **Opening the wrong dashboard.** Start with Istio Mesh when you do not know the service, and use Istio Workload's outbound panels when a service is slow.
> - **Taking the add-on stack for production monitoring.** The sample Prometheus has no permanent storage; the history you rely on may not survive its pod.

> *Counters keep their totals and rates forget, which is why every question here is a query over time, not a number.*

## Your mission: Measure The Failure Before You Fix It

You can now measure a failure with PromQL, read which side records it, remove the cause and prove the fix with the same query. Now prove it in a graded mission: `notification-service` in `metrics-demo` fails some of the time, and you have to measure it, remove the cause, and declare access logging for the namespace with a `Telemetry` object.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-060-02
```

Then start the mission:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-060/module-02/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-02/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-016-lab-060-02
astrona start ats-016-playground-060-02
```
