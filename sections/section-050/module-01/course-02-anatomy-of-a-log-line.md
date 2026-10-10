# The Anatomy Of A Line

A line in the default access log has about twenty fields separated by spaces, and none of them has a label. It looks impossible to read, but it is not. Six fields answer nearly every question, and once you know where they sit, the line becomes a readable record of one request. This part is the map of those fields.

## One line, annotated

Here is the line from a successful request, written by the client's sidecar proxy, with every field numbered:

```text
[2026-09-27T10:02:11.401Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 14 3 2 "-" "curl/8.4.0" "9c41..." "notification-service" "10.244.0.12:8084" outbound|80||notification-service.accesslog-demo.svc.cluster.local 10.244.0.9:52218 10.96.44.31:80 10.244.0.9:52216 - default
 ①                          ②                      ③   ④ ⑤             ⑥   ⑦   ⑧  ⑨  ⑩ ⑪  ⑫    ⑬          ⑭        ⑮                ⑯                   ⑰                                                          ⑱
```

| # | Field | Reads as |
| --- | --- | --- |
| ① | start time | when the request began, in UTC (Coordinated Universal Time) |
| ② | the request | `"<method> <path> <protocol>"` |
| ③ | **response code** | the HTTP status the client received |
| ④ | **response flags** | **why the request ended that way**; `-` means no proxy-level error |
| ⑤ | **response code details** | Envoy's longer explanation of the outcome |
| ⑥ | connection termination details | present when a connection-level event ended the request |
| ⑦ | upstream transport failure reason | TLS and connection errors, in quotes |
| ⑧⑨ | bytes received / sent | request and response body sizes |
| ⑩ | **duration** | total milliseconds, from the first byte received to the last byte sent |
| ⑪ | upstream service time | milliseconds the upstream took (the `x-envoy-upstream-service-time` header) |
| ⑫ | `x-forwarded-for` | the original client address chain, if any |
| ⑬ | user agent | the client program, here `curl` |
| ⑭ | request id | the `x-request-id` header: **the same value on both proxies' lines** |
| ⑮ | **authority** | the `Host` header, which routing matched on |
| ⑯ | **upstream host** | the address the proxy actually connected to, or `-` if none |
| ⑰ | **upstream cluster** | the Envoy cluster name: direction, port, subset and host |
| ⑱ | upstream local, downstream local and downstream remote addresses, requested server name, route name | the connection's addresses, the TLS server name and the route that matched |

Two words appear all through this table. The **upstream** is the destination the proxy sends the request to. The **downstream** is the caller that sent the request to the proxy. The fields in bold are the working set; the rest is context you need now and then.

## The six that answer most questions

Each of the six bold fields answers one question about the request. Read them in the order below, and most failures explain themselves.

### Response code and flag, together

The response code (③) and the **response flag** (④) only make sense as a pair. The flag is a short code that Envoy adds when the proxy itself ended or changed the request. A `503` with `-` and a `503` with `UH` are completely different incidents, and so are a plain `200` and a `200` that needed a retry.

### Response code details

Field ⑤ is Envoy's own description of the outcome. For most failures it repeats the flag in words, such as `no_healthy_upstream`, `route_not_found` or `response_timeout`. For an authorization denial it carries the whole answer: `rbac_access_denied_matched_policy[ns[x]-policy[y]-rule[0]]` names the exact policy and rule that refused the request. No other field does that.

### Duration against upstream service time

Read the duration (⑩) and the upstream service time (⑪) as a pair:

```text
   ⑩ 502   ⑪ 500     the upstream was slow: the time was spent in your service.
   ⑩ 502   ⑪ 2       the upstream was fast; 500ms went somewhere else:
                      connection setup, a queue, a retry, an injected delay.
   ⑩ 1000  ⑪ -       nothing came back at all. A timeout (see flag UT).
```

This comparison separates "the backend is slow" from "the mesh is slow". Without it, that question is a guess; with it, it is a measurement.

### Authority

Field ⑮ is the `Host` header, and it is what the proxy matched when it chose a route. When routing does something you cannot explain, check this field first: was the request addressed the way you think?

### Upstream host

Field ⑯ shows whether the proxy made a connection. An address means the proxy connected somewhere. A `-` means it never tried, so the failure happened before any network activity. This one field separates "the proxy could not decide where to go" from "the proxy went somewhere and it did not work".

### Upstream cluster

Field ⑰ names the exact destination the proxy chose, including the subset, for example `outbound|80||notification-service.accesslog-demo.svc.cluster.local`. Compare it with what you intended, and you catch a request sent to the wrong subset without running a single `istioctl proxy-config` command.

## Reading the fields from a live line

Now read the same fields from a line on your own cluster. Send one request, print four fields of the newest line with `awk`, then print the whole line:

<!-- astrona:playground:renew -->

```sh
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -X POST http://notification-service/notify
sleep 2
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1 \
  | awk '{print "status:   " $5 "\nflag:     " $6 "\ndetails:  " $7 "\nduration: " $12}'
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
```

You should see something like:

```text
status:   200
flag:     -
details:  via_upstream
duration: 6
[2026-10-09T22:25:21.259Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 9 6 5 "-" "curl/8.22.0" "3bc88af5-9463-9465-8763-bf38174c73de" "notification-service" "10.244.0.8:8084" outbound|80||notification-service.accesslog-demo.svc.cluster.local 10.244.0.9:51990 10.96.92.93:80 10.244.0.9:57726 - default
```

The `awk` field numbers count spaces, so the request field ② takes three of them (`"POST`, `/notify` and `HTTP/1.1"`). That is why the status, field ③, is `$5` in `awk`. `via_upstream` in the details field is the healthy case: the response came from the upstream service, not from the proxy. A response the proxy made itself, such as `no_healthy_upstream`, `response_timeout` or `rbac_access_denied…`, never reached your application.

These `awk` positions break easily. A quoted field that contains a space, such as a browser's user agent, shifts every position after it. That is a good reason to use JSON encoding whenever a program, not a person, reads these lines.

## Matching a request across two proxies

Field ⑭, the request id, joins the two sides of one request. Envoy creates the `x-request-id` header where the request enters the mesh and passes it on, so the client's line and the destination's line for the same request carry the same value. Take the request id from the `tester` pod's newest line, then search for it in both proxy logs:

```sh
REQUEST_ID=$(kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1 | awk '{print $16}')
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy | grep "$REQUEST_ID"
kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy | grep "$REQUEST_ID"
```

Each `grep` prints one line: the client's line and the destination's line for the same request. On a busy service, this is the difference between "there are errors" and "here is what happened to this request on both sides". Distributed tracing builds on the same header and carries it further.

There is one catch. The id only travels on if your application forwards the header. Istio creates and logs it, but a service that does not copy `x-request-id` to its own outgoing calls breaks the chain at that hop.

## JSON, when a program is reading

With `accessLogEncoding: JSON`, the same information arrives with field names:

```json
{"start_time":"...","method":"POST","path":"/notify","response_code":200,
 "response_flags":"-","duration":3,"upstream_service_time":"2",
 "authority":"notification-service","upstream_host":"10.244.0.12:8084",
 "upstream_cluster":"outbound|80||notification-service.accesslog-demo.svc.cluster.local",
 "request_id":"9c41..."}
```

Nothing depends on field position, `jq` works, and a log system can index each field. The cost is that it is harder to read in a terminal. That is why many teams use TEXT in development and JSON in production.

You can now read any line in the default format: the status and flag together, the response code details, the duration against the upstream service time, the authority, the upstream host and the upstream cluster. You can also find one request on both proxies by its request id. What the flags themselves mean, and what it tells you which proxy wrote a line, is still open.

## Common pitfalls

> [!WARNING]
> - **Reading the status code without the flag.** They are different facts; the pair is the diagnosis.
> - **Skipping the response code details.** For authorization denials it is the only field that names the policy responsible.
> - **Confusing duration with upstream service time.** The difference between them is time spent somewhere other than your application.
> - **Ignoring the upstream host field.** A `-` there means no connection was attempted, a fact no other field states.
> - **Reading the TEXT format by position in a script.** Quoted fields can contain spaces, and the positions shift. Use JSON encoding.
> - **Assuming the request id reaches every hop.** It travels on only if applications forward the header.
