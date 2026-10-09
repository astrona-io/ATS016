# Debug A 503 Caused By An mTLS Mismatch

Mutual TLS (mTLS) is TLS in which both sides of a connection present a certificate, so the connection is encrypted and both identities are checked. In Istio, two different objects set up the two ends of an mTLS connection, and two different people often write them. **`PeerAuthentication`** sets what the **server** side accepts on inbound connections. **`DestinationRule`** sets what the **client** side sends. Neither object mentions the other, and neither is invalid on its own.

Most `503` errors come from a client that cannot find its destination. This one comes from a client that finds the destination and cannot agree with it on how to connect. The evidence is as much in what is missing from one access log as in what is written in the other.

This module has three parts. **Two Objects, Two Ends Of One Connection** explains what each object controls, the modes on both sides, which combinations fail, and what the settings become inside the proxies. **The Signature** reads the failure from the access logs of both proxies and confirms it against the destination's effective mTLS mode. **Fixing It, And Proving Encryption** chooses which end to change, fixes it, and proves that the traffic is encrypted and not only working. A graded lab follows the third part.

## Learning objectives

After this module you can:

- Name the object that sets each side of mTLS, and the field each one uses.
- List the modes on both sides and predict which combinations work.
- Explain what `PERMISSIVE` does, and why it lets mismatches go unnoticed.
- Recognise the signature of a `UF` flag on the client's proxy with nothing on the destination's proxy, and explain why the destination logs nothing.
- Read a workload's effective mTLS mode instead of a single policy object.
- Decide which of the two objects to change, and explain why not the other.
- Prove that traffic is encrypted after the fix, not only working.
- Recognise the same signature from a caller outside the mesh, and fix it correctly.

## Before you start

You need Kubernetes basics: namespaces, Deployments, Services, and the commands `kubectl logs` and `kubectl exec`. You also need to read an Envoy access log line. Each sidecar proxy (the Envoy container Istio adds to every pod in the mesh) writes one line per request. The response flag, for example `UF` for upstream connection failure, says why the request ended, and the upstream host field shows the address the proxy connected to, or `-` if none. A request between two pods in the mesh is logged by the client's proxy on the way out and by the destination's proxy on the way in.

Your playground is one `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` on your PATH. Access logging is on for the whole mesh, which this module depends on. The namespace **`mtlsfail-demo`** has sidecar injection switched on and holds these objects:

| Kubernetes name | What it is |
| --- | --- |
| `notification-service` | Service on port `80`, in front of `notification-service-v1` |
| `notification-service-v1` | The application: nginx answering `["EMAIL"]` on any path |
| `tester` | A client pod with `curl`. Every test request is sent from here |
| `default` (`PeerAuthentication`) and `notification` (`DestinationRule`) | Two objects that are **already in conflict**, so every request fails |

Diagnosing that conflict is the subject of this module, so do not read the two objects until a part asks you to.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
