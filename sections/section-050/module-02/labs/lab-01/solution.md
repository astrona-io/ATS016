# Solution: A 503 Where The Destination Log Is Empty

The grader checks three things: a `POST` returns `200`; the `PeerAuthentication` is still `STRICT` and the `DestinationRule` `notification` still exists without `tls.mode: DISABLE`; and the destination proxy reports `connection_security_policy="mutual_tls"` with no plain text. This walkthrough finds the mismatch from the logs, fixes the client end, and proves all three.

## Step 1: Read the pair of logs

Read the newest access log lines on the client's proxy and on the destination's proxy:

```sh
kubectl -n mtlsfail-demo logs deploy/tester -c istio-proxy --tail=3
echo '--- destination ---'
kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

The output looks something like this (shortened to the access log lines; the other lines are start-up messages of the proxy):

```text
[2026-10-09T22:26:48.133Z] "POST /notify HTTP/1.1" 503 UC upstream_reset_before_response_started{connection_termination} - "-" 0 95 1 - "-" "curl/8.22.0" "56fd0f76-70e7-9135-a60e-66799df83b62" "notification-service" "10.244.0.8:8084" outbound|80||notification-service.mtlsfail-demo.svc.cluster.local 10.244.0.9:45690 10.96.172.178:80 10.244.0.9:36914 - default
--- destination ---
[2026-10-09T22:26:48.133Z] "- - -" 0 NR filter_chain_not_found - "-" 0 0 0 - "-" "-" "-" "-" "-" - - 10.244.0.8:8084 10.244.0.9:45690 - -
```

If the client's newest line is older than your request, wait two seconds and read the logs again: the proxy writes its access log in short batches. Four details together are the whole diagnosis:

| Observation | Means |
| --- | --- |
| client flag `UC` | upstream connection termination: the connection was set up, then the other side closed it |
| details `upstream_reset_before_response_started{connection_termination}` | the connection was closed before any response began |
| upstream host `10.244.0.8:8084` | an **address**, so the destination was found and reached |
| destination line `"- - -" 0 NR filter_chain_not_found` | a connection-level line, not a request: no filter chain on the inbound listener accepted the connection |

The last row says where it failed. A proxy writes a request line when an HTTP request completes. Here the destination's inbound listener found no filter chain for a plain-text connection, because with `STRICT` every chain requires TLS, so it closed the connection one level below HTTP. So the failure is **below HTTP, on the receiving side**. That separates it from `NC` and `UH`, where the upstream host field would be `-`.

## Step 2: Rule out the look-alike first

The same signature appears when a caller **outside the mesh** talks to a `STRICT` workload. Check that before you touch any policy:

```sh
kubectl -n mtlsfail-demo get pods
istioctl proxy-status | grep mtlsfail-demo
```

Both pods are `2/2` and both appear in `istioctl proxy-status`, which lists every proxy connected to `istiod`. The caller is in the mesh, so this is a configuration mismatch, not a missing sidecar.

## Step 3: Read both ends

Read the destination's effective mTLS mode, then the client's TLS setting:

```sh
export POD=$(kubectl -n mtlsfail-demo get pod -l app=notification-service -o jsonpath='{.items[0].metadata.name}')
istioctl x describe pod $POD -n mtlsfail-demo | grep -i -A2 'Effective PeerAuthentication'
kubectl -n mtlsfail-demo get destinationrule -o yaml | grep -A3 'tls:'
```

The output looks something like this (shortened to the lines that matter):

```text
   Workload mTLS mode: STRICT
      tls:
        mode: DISABLE
```

The server requires mTLS; the client is told to send plain text. Each object is valid and neither mentions the other, which is why this survived review.

Use `istioctl x describe pod` instead of reading the `PeerAuthentication` directly. Mesh, namespace and workload policies merge, narrowest first and per port, and only the effective value accounts for that.

## Step 4: Fix the client, not the server

`STRICT` is the intended rule and the task forbids relaxing it. `tls: DISABLE` on the client is the mistake.

Remove the client's traffic policy, which holds only that TLS override. Istio's default for traffic between sidecars is already mesh mTLS, so deleting the setting is better than setting it explicitly: one less thing to drift. The `DestinationRule` itself stays:

```sh
kubectl -n mtlsfail-demo patch destinationrule notification --type json \
  -p '[{"op":"remove","path":"/spec/trafficPolicy"}]'
kubectl -n mtlsfail-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

```text
200
```

Setting `tls.mode: ISTIO_MUTUAL` would also be correct. `MUTUAL` would not: it means "mutual TLS with certificates I supply" and needs a certificate reference.

Submit to see the first checks pass:

```sh
astrona submit -c sections/section-050/module-02/labs/lab-01
```

## Step 5: Prove encryption, not just success

A `200` would also appear if someone had "fixed" this by setting the server to `PERMISSIVE` and left the client sending plain text. Those are different outcomes with the same status code. Ask the destination proxy how the connections were secured:

```sh
kubectl -n mtlsfail-demo exec deploy/notification-service-v1 -c istio-proxy -- \
  pilot-agent request GET stats/prometheus | grep istio_requests_total \
  | grep -o 'connection_security_policy="[^"]*"' | sort | uniq -c
```

Each output line is a count followed by one value of the label. After the fix, every series reports `connection_security_policy="mutual_tls"`. The first line may be an `INFO GOMEMLIMIT` message from `pilot-agent`; ignore it. The label means something on the **destination**: the receiving proxy is the one that knows how the connection was secured. `none` here would mean working, unencrypted traffic and a fix on the wrong end.

Finally, read the destination's log again:

```sh
kubectl -n mtlsfail-demo logs deploy/notification-service-v1 -c istio-proxy --tail=3
```

The newest line is now an HTTP request line, `"POST /notify HTTP/1.1" 200 - via_upstream`, served against the `inbound|8084||` cluster. During the failure there was only the `filter_chain_not_found` line; request lines are the proof that the connection now completes.

Submit again. All three checks should pass:

```sh
astrona submit -c sections/section-050/module-02/labs/lab-01
```

## Common mistakes

- Relaxing the `PeerAuthentication` to `PERMISSIVE` to make the error go away. That hides a client misconfiguration and weakens security for every caller.
- Looking only at one side. The client's `UC` and the destination's `filter_chain_not_found` line only make sense together.
- Forgetting that with no `tls` setting in a `DestinationRule`, the client uses mesh mTLS by default, so *adding* one can only make things worse here.
- Confusing this with a caller outside the mesh. Check whether the client has a sidecar before you edit policy.
- Deleting the `DestinationRule` instead of removing its TLS setting.
- Trusting a `200` as proof of encryption.

## Practice variations

- Invert the mistake: set the server to `DISABLE` and the client to `ISTIO_MUTUAL`, then read the log signature.
- Remove the sidecar from the client and reproduce the same `503` with a different root cause.
- Set a port-level exception with `portLevelMtls` so one port works and another fails.
