# Part 2 — The Anatomy Of A Line

> Prerequisite: [Part 1 — Turning Logging On, And Scoping It](./course-01-enabling-and-scoping-logs.md). Next: [Part 3 — Flags, And Which Proxy Wrote The Line](./course-03-flags-and-which-proxy.md).

The default access log line is about twenty space-separated fields with no labels. It looks impenetrable and is not: six fields answer nearly every question, and knowing where they sit turns a wall of text into a readable record. This part is that map.

## One line, annotated

Take the line from a successful request and mark the fields that matter:

```text
[2026-09-27T10:02:11.401Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 14 3 2 "-" "curl/8.4.0" "9c41..." "notification-service" "10.244.0.12:8084" outbound|80||notification-service.accesslog-demo.svc.cluster.local 10.244.0.9:52218 10.96.44.31:80 10.244.0.9:52216 - default
 ①                          ②                      ③   ④ ⑤             ⑥   ⑦   ⑧  ⑨  ⑩ ⑪  ⑫    ⑬          ⑭        ⑮                ⑯                   ⑰                                                          ⑱
```

| # | Field | Reads as |
| --- | --- | --- |
| ① | start time | when the request began, in UTC |
| ② | the request | `"<method> <path> <protocol>"` |
| ③ | **response code** | the status the client received |
| ④ | **response flags** | **why it ended that way** — `-` for no proxy-level error |
| ⑤ | **response code details** | Envoy's longer explanation |
| ⑥ | connection termination details | present when a connection-level event ended it |
| ⑦ | upstream transport failure reason | TLS and connection errors, in quotes |
| ⑧⑨ | bytes received / sent | request and response body sizes |
| ⑩ | **duration** | total milliseconds, client's first byte to last byte sent |
| ⑪ | upstream service time | milliseconds the upstream took (the `x-envoy-upstream-service-time` header) |
| ⑫ | `x-forwarded-for` | the original client chain, if any |
| ⑬ | user agent | |
| ⑭ | request id | `x-request-id` — **the same value on both proxies' lines** |
| ⑮ | **authority** | the `Host` header — what routing matched on |
| ⑯ | **upstream host** | the address actually connected to, or `-` if none |
| ⑰ | **upstream cluster** | the four-field cluster name from [section 040](../../section-040/module-01/course-03-clusters-and-endpoints.md) |
| ⑱ | downstream / local addresses, route name, requested server name | connection endpoints and TLS SNI |

The six in bold are the working set. Everything else is context you will occasionally need.

## The six that answer most questions

**Response code (③) and flags (④) together.** Neither alone is enough. `503` with `-` and `503` with `UH` are entirely different incidents; so are `200` and `200` preceded by a retry. [Part 3](./course-03-flags-and-which-proxy.md) is the flag taxonomy.

**Response code details (⑤).** Envoy's own sentence about the outcome. For most failures it restates the flag (`no_healthy_upstream`, `route_not_found`, `response_timeout`). For authorization it carries the whole answer — `rbac_access_denied_matched_policy[ns[x]-policy[y]-rule[0]]` names the exact policy and rule that refused, and no other field does.

**Duration (⑩) against upstream service time (⑪).** Read as a pair:

```text
   ⑩ 502   ⑪ 500     the upstream was slow. Your service.
   ⑩ 502   ⑪ 2       the upstream was fast; 500ms went somewhere else —
                      connection setup, a queue, a retry, an injected delay.
   ⑩ 1000  ⑪ -       nothing came back at all. A timeout (see flag UT).
```

That comparison separates "the backend is slow" from "the mesh is slow", which is otherwise an argument rather than a measurement.

**Authority (⑮).** The `Host` header, which is what virtual host selection matched on ([module 040-01 Part 2](../../section-040/module-01/course-02-routes.md)). When routing does something inexplicable, this field is the first place to check whether the request was addressed the way you think.

**Upstream host (⑯).** An address means a connection was made. A `-` means none was attempted, and the failure happened before any network activity. This single field separates "could not decide where to go" from "went somewhere and it did not work".

**Upstream cluster (⑰).** The four-field name identifies the exact destination chosen, including the subset. Reading it against what you intended catches a wrong-subset problem without running a single `proxy-config` command.

> [!TIP]
> **Try it — one request, read field by field**
>
> ```sh
> kubectl -n accesslog-demo exec deploy/tester -- \
>   curl -s -o /dev/null -X POST http://notification-service/notify
> kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1 \
>   | awk '{print "status:   " $4 "\nflag:     " $5 "\ndetails:  " $6 "\nduration: " $(NF-8)}'
> kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
> ```
>
> Expect something like:
>
> ```text
> status:   200
> flag:     -
> details:  via_upstream
> duration: 3
> [2026-09-27T10:04:55.118Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 14 3 2 ...
> ```
>
> `via_upstream` in the details field is the healthy case: the response came from the upstream service rather than being generated by the proxy. That distinction reappears constantly — a proxy-generated response (`no_healthy_upstream`, `response_timeout`, `rbac_access_denied…`) never touched your application.
>
> The `awk` positions above are fragile by nature — a quoted field containing spaces shifts them — which is a practical argument for JSON encoding when anything other than a human reads these lines.

## Matching a request across two proxies

Field ⑭, the request id, is the join key. Envoy generates `x-request-id` at the edge and propagates it, so the client's line and the destination's line for the same request carry the same value.

That makes a precise two-sided lookup possible:

```sh
RID=$(kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1 | awk '{print $14}')
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy | grep "$RID"
kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy | grep "$RID"
```

On a busy service this is the difference between "there are errors" and "here is what happened to *this* request on both sides". It is also the mechanism distributed tracing builds on — the same header, carried further.

One caveat worth stating: propagation depends on your application forwarding the header. Istio generates and logs it, but a service that does not pass `x-request-id` on to its own outbound calls breaks the chain at that hop.

## JSON, when something else is reading

With `accessLogEncoding: JSON`, the same information arrives with names:

```json
{"start_time":"...","method":"POST","path":"/notify","response_code":200,
 "response_flags":"-","duration":3,"upstream_service_time":"2",
 "authority":"notification-service","upstream_host":"10.244.0.12:8084",
 "upstream_cluster":"outbound|80||notification-service.accesslog-demo.svc.cluster.local",
 "request_id":"9c41..."}
```

Nothing depends on field position, `jq` works, and a log pipeline can index individual fields. The cost is readability at a terminal — which is why many clusters run TEXT in development and JSON in production.

> [!WARNING]
> **Pitfalls in reading a line**
>
> - **Reading the status code without the flag.** They are different facts; the pair is the diagnosis.
> - **Skipping `RESPONSE_CODE_DETAILS`.** For authorization denials it is the only field that names the responsible policy.
> - **Confusing duration with upstream service time.** Their difference is the time spent somewhere other than your application.
> - **Ignoring the upstream host field.** A `-` there means no connection was attempted — a fact no other field states.
> - **Parsing the TEXT format positionally in a script.** Quoted fields contain spaces and the positions shift. Use JSON encoding.
> - **Assuming the request id will be present downstream.** It propagates only if applications forward the header.

> *Six fields carry the diagnosis: status, flag, details, duration pair, authority, upstream host and cluster — the rest is context.*

## Reference

- [Istio default access log format](https://istio.io/latest/docs/tasks/observability/logs/access-log/#default-access-log-format) — the authoritative field order for the line above.
- [Envoy access log format strings](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage#format-strings) — every command operator, including the ones not in the default format.
- [Response code details](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage#config-access-log-format-response-code-details) — the vocabulary of field ⑤.
- [Distributed tracing](https://istio.io/latest/docs/tasks/observability/distributed-tracing/overview/) — what `x-request-id` and the trace headers enable once applications propagate them.
