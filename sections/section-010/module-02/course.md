# Summarise A Workload With describe, Capture A Cluster With bug-report

You are given the name of one pod and a complaint about it. Somewhere in its namespace there may be a `VirtualService`, a `DestinationRule`, a `PeerAuthentication` and an `AuthorizationPolicy`, written by different people at different times. Only one question matters: which of them actually apply to this pod, and what do they add up to?

Answering that by listing objects and reading YAML is slow and easy to get wrong. Whether an object applies depends on hosts, selectors and scope rules, not on what any single file says. A `PeerAuthentication` sets whether a workload accepts plain text, mutual TLS (mTLS) or both on inbound connections. An `AuthorizationPolicy` allows or denies requests to a workload. Mutual TLS means both sides of a connection present a certificate, so the connection is encrypted and both identities are checked.

This module covers three tools for three versions of the problem, in three parts. **What describe Resolves For One Workload** shows how `istioctl x describe pod` combines every object that touches one pod into one page, and how the scope rules decide the result. **Making A Proxy Narrate One Decision** raises one Envoy log scope on a running pod, so the sidecar proxy writes down why it allowed or denied a request, and then puts the level back. A graded lab follows this part. **Capturing A Cluster With bug-report** produces an archive of the control plane and selected proxies that someone else can read later. A second graded lab follows that part.

## Learning objectives

After this module you can:

- Explain how Istio decides which objects apply to a workload, including scope precedence for `PeerAuthentication`.
- Run `istioctl x describe pod` and say what each section of its output tells you.
- State a workload's effective mTLS mode and the routes that apply to it from `describe` output alone.
- Explain the difference between how `PeerAuthentication` and `AuthorizationPolicy` combine.
- Explain what Envoy log scopes are, and why one scope at `debug` is different from every scope at `debug`.
- Raise one log scope at runtime, read the resulting decision, and put the level back.
- Produce a `bug-report` archive limited to chosen workloads and a time window, and say what it contains.
- Choose between `describe`, a scoped log level and `bug-report` for a given situation.

## Before you start

You need Kubernetes basics: namespaces, Deployments, Services, pod labels, and the commands `kubectl get`, `kubectl logs` and `kubectl exec`. You should also know `istioctl analyze`, which checks that the Istio configuration fits together as a whole. `describe` is the next command once the configuration is coherent and you still do not know what it does to one pod.

Your playground is a single-node `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` on your PATH. `istiod` is Istio's control plane: it turns Istio resources into proxy configuration and sends it to every sidecar proxy. A sidecar proxy (Envoy) is a proxy container that Istio adds to each pod; all inbound and outbound traffic of the pod passes through it. The namespace **`describe-demo`** has sidecar injection switched on and runs these workloads:

| Workload | What it is |
| --- | --- |
| `notification-service-v1` | A Deployment with the label `version: v1`, behind the Service `notification-service` on port `80` |
| `tester` | A client pod with `curl`. Every test request in this module is sent from here |

Four Istio objects apply to the `notification-service` workload:

- a namespace-wide `PeerAuthentication` in `STRICT` mode, so the workload accepts only mTLS connections;
- a `DestinationRule` that defines the subset `v1`;
- a `VirtualService` that routes to that subset;
- an `AuthorizationPolicy` that allows only the `POST` method.

Nothing here is broken. This module is about reading a working system, which is the harder skill.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
