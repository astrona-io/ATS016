# Troubleshoot With Kiali

Looking at one pod or one pair of pods works once you know where to look. It does not work when the report says "something is slow" and forty services are involved. You first need one view of the whole mesh that shows which pair of workloads is failing.

Kiali gives you that view. Kiali is the Istio console: a web application that draws the services in the mesh as a graph and checks their Istio configuration. Here is the key fact about it: **Kiali draws pictures, it does not collect data.** It stores nothing and measures nothing of its own. Every number in its graph comes from the metrics that the sidecar proxies record, and every warning comes from the same checks that `istioctl analyze` runs. So a red line in the graph points at a real problem, but it is only a place to start looking, not an answer.

The module has three parts. **What Kiali Is Built From** covers Kiali's two data sources, how a request metric becomes a line in the graph, and why the graph is empty when either source is missing. **Reading The Graph** explains what a node, an edge and a colour say, uses fault injection to turn an edge red on purpose, and explains why a healthy service can be missing from the graph. **Validations, Badges And Cross-Checking** puts Kiali's configuration checks next to `istioctl analyze` and the security padlock next to the metric it comes from, and ends with a method that uses Kiali to find a problem, not to explain it. A graded lab follows the third part.

## Learning objectives

After this module you can:

- Name Kiali's two data sources and explain why it shows nothing without either one.
- Describe how a request metric becomes a node and an edge in the graph.
- Choose the graph display options that answer a given question.
- Explain exactly what a red edge says, and what it does not say.
- Explain why a running, healthy service can be missing from the graph.
- Find the same messages as `istioctl analyze` inside Kiali, and say when to use each.
- Explain the security padlock, and check it against the metric it comes from.
- Check anything Kiali shows against the proxy data underneath it.

## Before you start

You need Kubernetes basics: namespaces, Deployments, Services, pod labels, `kubectl exec` and `kubectl logs`. You also need two Istio basics. A sidecar proxy (Envoy) is a proxy container that Istio adds to each pod; all inbound and outbound traffic of the pod passes through it. A `VirtualService` is the Istio resource that tells the sidecar proxies how to route requests for a host.

You also need one fact about Istio's metrics. Every sidecar proxy counts the requests it handles in a metric called `istio_requests_total`. Each count carries labels: who called, who was called, the response code, and `connection_security_policy`, which says whether the connection used mutual TLS (mTLS). mTLS is TLS where both sides present a certificate, so the connection is encrypted and both identities are checked.

Your playground is one `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` on your PATH. The `istio-system` namespace also runs two add-ons. **Prometheus** is a monitoring system that collects metrics from the proxies and stores them as time series. **Kiali** reads those metrics to draw its graph. The namespace **`kiali-demo`** has sidecar injection switched on and runs these workloads:

| Workload | What it is |
| --- | --- |
| `notification-service-v1` | A Deployment behind the Service `notification-service` on port `80`. It answers `["EMAIL"]` |
| `tester` | A client pod with `curl`. Every test request in this module is sent from here |

No traffic flows when the playground starts, so the Kiali graph starts empty. That is on purpose. Kiali is a web page, and whether your browser can reach it depends on how you are connected to the playground. So every hands-on step in this module also has a command-line form that reads the same data Kiali draws from.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
