# The Anatomy Of A Line

Astronaut, a line in the flight log (the access log your ship's communications officer writes) has about twenty fields separated by spaces, and none of them has a label. It looks impossible to read, but it is not. Six fields answer nearly every question, and once you know where they sit, the wall of text becomes a readable record. This part is that map.

## One line, annotated

Here is the line from a successful request, with every field numbered:

```text
[2026-09-27T10:02:11.401Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 14 3 2 "-" "curl/8.4.0" "9c41..." "notification-service" "10.244.0.12:8084" outbound|80||notification-service.accesslog-demo.svc.cluster.local 10.244.0.9:52218 10.96.44.31:80 10.244.0.9:52216 - default
 ①                          ②                      ③   ④ ⑤             ⑥   ⑦   ⑧  ⑨  ⑩ ⑪  ⑫    ⑬          ⑭        ⑮                ⑯                   ⑰                                                          ⑱
```

| # | Field | Reads as |
| --- | --- | --- |
| ① | start time | when the request began, in UTC (Coordinated Universal Time) |
| ② | the request | `"<method> <path> <protocol>"` |
| ③ | **response code** | the status the client received |
| ④ | **response flags** | **why it ended that way**; `-` means no proxy-level error |
| ⑤ | **response code details** | Envoy's longer explanation |
| ⑥ | connection termination details | present when a connection-level event ended it |
| ⑦ | upstream transport failure reason | TLS and connection errors, in quotes |
| ⑧⑨ | bytes received / sent | request and response body sizes |
| ⑩ | **duration** | total milliseconds, from the client's first byte to the last byte sent |
| ⑪ | upstream service time | milliseconds the upstream took (the `x-envoy-upstream-service-time` header) |
| ⑫ | `x-forwarded-for` | the original client chain, if any |
| ⑬ | user agent | |
| ⑭ | request id | `x-request-id`: **the same value on both proxies' lines** |
| ⑮ | **authority** | the `Host` header: what routing matched on |
| ⑯ | **upstream host** | the address the proxy actually connected to, or `-` if none |
| ⑰ | **upstream cluster** | the cluster name: direction, port, subset and host |
| ⑱ | downstream / local addresses, route name, requested server name | connection endpoints and the TLS server name |

The **upstream** is the destination the proxy sends the signal to; the **downstream** is the caller that sent it. The fields in bold are the working set. The rest is context you will need now and then.

## The six that answer most questions

Each of the six bold fields answers one question about the signal. Read them in this order and most failures explain themselves.

### Response code and flag, together

The response code (③) and the **response flag** (④) only make sense as a pair. The flag is the short code the communications officer stamps on a failed signal in the flight log. A `503` with `-` and a `503` with `UH` are completely different incidents. So are a plain `200` and a `200` that needed a retry.

### Response code details

Field ⑤ is Envoy's own sentence about the outcome. For most failures it repeats the flag in words (`no_healthy_upstream`, `route_not_found`, `response_timeout`). For an authorization denial it carries the whole answer: `rbac_access_denied_matched_policy[ns[x]-policy[y]-rule[0]]` names the exact policy and rule that refused the signal. No other field does that.

### Duration against upstream service time

Read the duration (⑩) and the upstream service time (⑪) as a pair:

```text
   ⑩ 502   ⑪ 500     the upstream was slow. Your service.
   ⑩ 502   ⑪ 2       the upstream was fast; 500ms went somewhere else —
                      connection setup, a queue, a retry, an injected delay.
   ⑩ 1000  ⑪ -       nothing came back at all. A timeout (see flag UT).
```

This comparison separates "the backend is slow" from "the mesh is slow". Without it, that question is an argument; with it, it is a measurement.

### Authority

Field ⑮ is the `Host` header, and it is what the proxy matched when it chose a route. When routing does something you cannot explain, check this field first: was the request addressed the way you think?

### Upstream host

Field ⑯ shows whether a connection was made. An address means the proxy connected somewhere. A `-` means it never tried, so the failure happened before any network activity. This one field separates "could not decide where to go" from "went somewhere and it did not work".

### Upstream cluster

Field ⑰ names the exact destination the proxy chose, including the subset, for example `outbound|80||notification-service.accesslog-demo.svc.cluster.local`. Compare it with what you intended, and you catch a wrong-subset problem without running a single `istioctl proxy-config` command.

<!-- astrona:playground:renew -->

### See it in your playground

Send one request, print four fields of the newest flight log line, then print the whole line:

```sh
kubectl -n accesslog-demo exec deploy/tester -- \
  curl -s -o /dev/null -X POST http://notification-service/notify
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1 \
  | awk '{print "status:   " $4 "\nflag:     " $5 "\ndetails:  " $6 "\nduration: " $(NF-8)}'
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1
```

You should see something like:

```text
status:   200
flag:     -
details:  via_upstream
duration: 3
[2026-09-27T10:04:55.118Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 14 3 2 ...
```

`via_upstream` in the details field is the healthy case: the response came from the upstream service, not from the proxy. You will see this difference again and again. A response the proxy made up itself (`no_healthy_upstream`, `response_timeout`, `rbac_access_denied…`) never touched your application.

The `awk` positions above break easily: a quoted field that contains a space shifts every position after it. That is a good reason to use JSON encoding whenever a program, not a person, reads these lines.

## Matching a request across two proxies

Field ⑭, the request id, joins the two sides of one signal. Envoy creates the `x-request-id` header where the request enters the mesh and passes it on. So the client's line and the destination's line for the same request carry the same value.

### Find one request on both sides

Take the request id from the tester's newest line, then search for it in both flight logs:

```sh
RID=$(kubectl -n accesslog-demo logs deploy/tester -c istio-proxy --tail=1 | awk '{print $14}')
kubectl -n accesslog-demo logs deploy/tester -c istio-proxy | grep "$RID"
kubectl -n accesslog-demo logs deploy/notification-service-v1 -c istio-proxy | grep "$RID"
```

`RID` holds the request id. On a busy service, this is the difference between "there are errors" and "here is what happened to *this* request on both sides". Distributed tracing builds on the same header, carried further.

There is one catch. The id only travels on if your application forwards the header. Istio creates and logs it, but a service that does not pass `x-request-id` on to its own outgoing calls breaks the chain at that hop.

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

## Common pitfalls

> [!WARNING]
> - **Reading the status code without the flag.** They are different facts; the pair is the diagnosis.
> - **Skipping the response code details.** For authorization denials it is the only field that names the policy responsible.
> - **Confusing duration with upstream service time.** The difference between them is time spent somewhere other than your application.
> - **Ignoring the upstream host field.** A `-` there means no connection was attempted, a fact no other field states.
> - **Reading the TEXT format by position in a script.** Quoted fields contain spaces and the positions shift. Use JSON encoding.
> - **Assuming the request id reaches every hop.** It travels on only if applications forward the header.

> *Six fields carry the diagnosis: status, flag, details, the duration pair, authority, and the upstream host and cluster. The rest is context.*
