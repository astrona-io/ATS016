# Summary

A `503` between two healthy workloads can come from a disagreement about how to connect. This module showed how an mTLS mismatch arises, how to recognise it from the access logs, and how to fix it so that the traffic is encrypted and not only working.

## What you learned

Two unrelated objects set the two ends of an mTLS connection. `PeerAuthentication` (`spec.mtls.mode`) sets what the server accepts: `STRICT`, `PERMISSIVE`, `DISABLE` or `UNSET`. `DestinationRule` (`spec.trafficPolicy.tls.mode`) sets what the client sends: `ISTIO_MUTUAL`, `SIMPLE`, `MUTUAL` or `DISABLE`. Nothing compares the two. `STRICT` with `DISABLE` fails, `DISABLE` with `ISTIO_MUTUAL` fails, and `PERMISSIVE` accepts anything, which is why mismatches stay hidden until a namespace becomes `STRICT`. With no `DestinationRule` at all, auto mTLS makes traffic between sidecar proxies use mTLS.

Inside the proxies, `PeerAuthentication` sets the transport socket on the filter chains of the destination's inbound listener on port `15006`, and `DestinationRule` sets the transport socket on the client's outbound cluster. When plain text reaches a listener that accepts only TLS, the destination's proxy closes the connection before an HTTP request exists. So the signature is a `503` with the flag `UF` and an upstream address on the client's proxy, and **no line at all** on the destination's proxy. `istioctl x describe pod` shows the destination's effective mTLS mode after all policies are merged.

The fix goes on the client. Keep the server `STRICT`, and remove the `tls` block from the `DestinationRule` with a JSON Patch, so that the default applies and the rest of the object stays. A caller with no sidecar proxy gives the same server-side signature but has no client-side log, shows `1/1` and is missing from `istioctl proxy-status`; the fix there is to bring the caller into the mesh, or to exempt one port with `portLevelMtls`. The key facts to remember are these:

- No `DestinationRule` is the safe default for traffic inside the mesh.
- `UF`, an upstream address and a silent destination point at the transport layer on the receiving side.
- Relaxing the server to `PERMISSIVE` hides the failure for every caller and removes the encryption guarantee.
- Prove a fix three ways: a `200`, `connection_security_policy="mutual_tls"` on the destination's proxy, and lines in the destination's access log.

<!-- astrona:playground:destroy -->
