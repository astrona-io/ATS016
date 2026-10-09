# Check Control Plane Health

When something in the mesh goes wrong, people usually look at the workload that fails. Often the better place to look is `istiod`, Istio's control plane. `istiod` turns Istio resources into proxy configuration and sends it, together with certificates, to every sidecar proxy. A sidecar proxy (Envoy) is a proxy container that Istio adds to each pod; all inbound and outbound traffic of the pod passes through it.

People look at the control plane last because a broken control plane does not look like an outage. Requests keep succeeding and dashboards stay green. What stops is *change*, and nothing reports that change has stopped. A **data plane** failure, a problem in the proxies that carry the requests, shows up at once as failed requests. A **control plane** failure shows up as something missing: configuration that never takes effect, pods that are never created, or certificates that quietly expire.

The module has four parts. **Four Jobs In One Process** splits `istiod` into the four jobs it does and shows how the mesh fails when each one stops. **The Instruments** reads the three sources of evidence about `istiod`: the pod status, the log and the metrics. **Take The Control Plane Away** scales `istiod` to zero on purpose and shows what keeps working and what stops. **Accepted, Never Applied** finds configuration that the cluster stored but `istiod` never sent to the proxies. A graded lab follows the fourth part.

## Learning objectives

After this module you can:

- Name the four jobs `istiod` does and describe how the mesh degrades when each one fails.
- Explain why running proxies keep serving traffic without a control plane, and what ends that period.
- Tell `istiod`'s readiness apart from its health, and say what a climbing restart count on a `Running` pod means.
- Read `istiod`'s metrics and explain `pilot_xds_pushes`, `pilot_total_xds_rejects`, `pilot_total_xds_internal_errors` and `pilot_proxy_convergence_time`.
- Explain why a counter that has never gone up is missing rather than zero.
- Predict what happens to new pods during a control plane outage, for each webhook `failurePolicy`.
- Explain how an invalid Istio object can be stored, and where the evidence of it shows up.
- Recognise the slow version of the same failure: a control plane short of memory or processor time.

## Before you start

You need Kubernetes basics: `kubectl` with `get`, `logs`, `exec` and `scale`, and what a Deployment, a ReplicaSet and a Service are. You do not need to write any Istio objects. This module is about the component that serves Istio objects to the proxies.

Your playground is a single-node `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` on your PATH. The namespace **`cphealth-demo`** has sidecar injection switched on and runs these workloads:

| Workload | What it is |
| --- | --- |
| `notification-service-v1` | A Deployment behind the Service `notification-service` on port `80`. It answers `["EMAIL"]` |
| `tester` | A client pod with `curl`. Every test request in this module is sent from here |

Nothing is broken when the playground starts. In one part you scale `istiod` to zero yourself. That is safe in the playground, because the cluster is yours and you can throw it away. On a shared cluster, the same command stops every team's deployments.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
