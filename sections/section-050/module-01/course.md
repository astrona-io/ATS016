# Read Envoy Access Logs And Response Flags

Astronaut, every signal in the mesh passes at least two communications officers: the sidecar proxy on the sending ship and the one on the receiving ship. Each officer keeps a flight log, the **access log**, and writes one line per signal. That line records what the proxy did, what the destination did, how long it took and, in a short code near the front, *why the signal ended the way it did*.

That short code is the **response flag**. `istioctl proxy-config` shows what a proxy is configured to do; the access log shows what it actually did. Learning to read the flag turns "the service is returning errors" into "the circuit breaker rejected it", "the route timeout fired" or "the request never left the client pod", before you open a single YAML file.

## Learning objectives

After this module you can:

- Switch on access logging for the whole mesh or for one namespace, and say which way to use when.
- Scope logging with a `Telemetry` object, including keeping only failed requests.
- Name the fields of the default access log format and find the response flag.
- Read the response code details and say when they matter more than the flag.
- Map the common flags to their causes, and recognise what a bare `-` means.
- Tell from a pair of logs whether a request ever reached its destination.
- Produce a timeout, a circuit breaker rejection, a routing miss and an authorization denial on purpose.
- Explain why an authorization denial is only explained on the destination proxy.
- Count the flags in a window of traffic to see which failure is most common.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** Namespaces, Deployments, Services, `kubectl logs` and `kubectl exec`.
- **What a sidecar proxy is.** Every pod in the mesh has an `istio-proxy` container next to the app, and every request in or out goes through it.
- **The four stages of a proxy's configuration.** A request meets a listener, then a route, then a cluster (a named destination such as `outbound|80||notification-service.accesslog-demo.svc.cluster.local`), then an endpoint (one pod address). Several flags name one of these stages directly.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` ready to use. The `demo` profile already switches on access logging for the whole mesh.

It has one planet, the namespace **`accesslog-demo`**, with sidecar injection switched on:

| Kubernetes name | What it is |
| --- | --- |
| `notification-service` | The beacon (Service) on port `80`, in front of `notification-service-v1` |
| `notification-service-v1` | The app: nginx answering `["EMAIL"]` on any path |
| `tester` | Your test ship: a pod with `curl`. Every test signal is sent from here |
| `access-logs` | A `Telemetry` object that scopes access logging to this namespace |

Traffic starts healthy. Some parts apply configuration that breaks traffic on purpose: a fault injection, a tight circuit breaker and a deny-all policy. Each one is removed again by a later step, and all of it stays inside this namespace.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts, in order

1. [Turning Logging On, And Scoping It](./course-01-enabling-and-scoping-logs.md)
2. [The Anatomy Of A Line](./course-02-anatomy-of-a-log-line.md)
3. [Flags, And Which Proxy Wrote The Line](./course-03-flags-and-which-proxy.md)
4. [Failures The Client's Proxy Decides](./course-04-failures-the-client-proxy-decides.md), followed by your mission
5. [A Denial On The Other Proxy](./course-05-a-denial-on-the-other-proxy.md)
6. [Wrap-Up: Mission Debrief](./course-06-wrap-up.md)

## Why this matters

In a live incident the access log is the fastest first move, because one command splits the problem in three. A flag of `-` with an error status means the application answered, so leave Istio alone. A `U` flag on the client means the request did not get where it was going, so follow the proxy's configuration. Lines on both proxies mean the request arrived, so look at the destination's policy and the response code details.
