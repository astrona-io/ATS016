# Debug A 503 Caused By An mTLS Mismatch

Astronaut, mutual TLS (mTLS) is a secret handshake: both ships show their ID badges before they talk. In Istio, two different objects set up the two ends of that handshake, and usually two different people write them. **`PeerAuthentication`** is the rule on the receiving ship's airlock: what the **server** will accept. **`DestinationRule`** tells the sending ship how to approach: what the **client** will send. Neither object mentions the other, and neither is invalid on its own.

Most `503` errors come from a client that cannot *find* its destination. This one comes from a client that found the destination perfectly well and cannot *agree* with it. The evidence is as much in what is missing from one flight log as in what is written in the other.

## Learning objectives

After this module you can:

- Name the object that sets each side of mTLS, and the field each one uses.
- List the modes on both sides and predict which combinations work.
- Explain what `PERMISSIVE` does, and why it lets mismatches go unnoticed.
- Recognise the signature of a `UF` flag on the client with nothing on the server, and explain why the destination logs nothing.
- Read a workload's effective mTLS mode instead of a single policy object.
- Decide which of the two objects to change, and explain why not the other.
- Prove traffic is encrypted after the fix, not just working.
- Recognise the same signature from a caller outside the mesh, and fix it correctly.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** Namespaces, Deployments, Services, `kubectl logs` and `kubectl exec`.
- **How to read an access log line.** Each sidecar proxy writes one line per request. The response flag (for example `UF`, upstream connection failure) says why the request ended, and the upstream host field shows the address the proxy connected to, or `-` if none.
- **Both sides log.** A request between two meshed pods is logged by the client's proxy on the way out and by the destination's proxy on the way in.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` ready to use. Access logging is on for the whole mesh, which this module depends on.

It has one planet, the namespace **`mtlsfail-demo`**, with sidecar injection switched on:

| Kubernetes name | What it is |
| --- | --- |
| `notification-service` | The beacon (Service) on port `80`, in front of `notification-service-v1` |
| `notification-service-v1` | The app: nginx answering `["EMAIL"]` on any path |
| `tester` | Your test ship: a pod with `curl`. Every test signal is sent from here |
| `default` (`PeerAuthentication`) and `notification` (`DestinationRule`) | Two objects that are **already in conflict**. Every request fails |

Diagnosing that conflict is what this module is about, so do not read the objects until a part asks you to.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts, in order

1. [Two Objects, Two Ends Of One Connection](./course-01-two-objects-two-ends.md)
2. [The Signature](./course-02-the-signature.md)
3. [Fixing It, And Proving Encryption](./course-03-fixing-and-proving-encryption.md), followed by your mission
4. [Wrap-Up: Mission Debrief](./course-04-wrap-up.md)

## Why this matters

A `UF` flag with an upstream address and a silent destination is one of the few signatures in Istio that points at a short, specific list of causes: an mTLS mode mismatch, a caller outside the mesh, or a wrong port. All three are configuration problems between two healthy workloads, and none of them ever shows up in an application log. Learn to read it, and you also learn the most important habit of mesh security: a working request is not proof of an encrypted one.
