# Find Configuration Errors With istioctl analyze

A `VirtualService` that routes to a subset no `DestinationRule` defines applies without an error. `kubectl get` lists it, and `kubectl describe` shows nothing wrong. The only symptom is that requests fail with `503`, several steps away from the object that caused it.

A `VirtualService` is the Istio resource that tells the sidecar proxies how to route requests for a host. A `DestinationRule` defines what happens to traffic for a host after routing, including named **subsets**: groups of pods selected by labels, such as `version: v1`. When a route names a subset that no `DestinationRule` defines, the route points at nothing.

This module is about that gap and the tool that closes it. Keep one sentence in mind: **`kubectl apply` checks one document at a time, and `istioctl analyze` checks the whole configuration set.** The analyzer reads every Istio object together, the same way `istiod` (Istio's control plane) does, and reports the references that do not resolve.

The module has three parts. **What The API Server Checks, And What It Cannot** follows one `kubectl apply` through every stage and shows why a missing subset passes all of them. **Reading What The Analyzer Says** takes one analyzer message apart: its severity, its `IST####` code and the object it blames, and how the exit code turns analysis into a check in a build pipeline. **Choosing The Right Analysis Source** compares analysing the cluster, a file on top of the cluster and a file alone, and ends with fixing a broken reference and proving the fix. A graded lab follows the third part.

## Learning objectives

After this module you can:

- Describe the stages a `kubectl apply` of an Istio resource passes through, and name which stage rejects what.
- Explain why a reference from one object to another cannot be checked when the object is applied.
- Run `istioctl analyze` against a namespace, the whole mesh, and a file that has not been applied yet.
- Read an analyzer message and name its severity, its `IST####` code and the object it blames.
- Explain why a `Warning` is often the real cause of a "my configuration does nothing" report.
- Use `--failure-threshold` and the exit code of the command to fail a build pipeline.
- Choose between `istioctl validate` and `istioctl analyze`, and state what each one cannot see.
- Fix an analyzer `Error` and prove the fix with a clean analyze run and real requests.

## Before you start

You need Kubernetes basics: namespaces, Deployments, Services, pod labels, and the commands `kubectl get`, `kubectl apply` and `kubectl exec`. You also need to know what a `VirtualService` and a `DestinationRule` are for. This module does not teach routing; it teaches how to find out that routing is broken.

Your playground is a single-node `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` on your PATH. Every pod in the mesh gets a sidecar proxy (Envoy): a proxy container that Istio adds to the pod, so that all inbound and outbound traffic of the pod passes through it. The namespace **`analyze-demo`** has sidecar injection switched on and runs these workloads:

| Workload | What it is |
| --- | --- |
| `notification-service-v1` | A Deployment with the label `version: v1`, behind the Service `notification-service` on port `80`. It answers `["EMAIL"]` |
| `tester` | A client pod with `curl`. Every test request in this module is sent from here |

The namespace also holds a `DestinationRule` and a `VirtualService` that are **broken on purpose**. Finding out how is the subject of this module, so run the analyzer before you read their YAML. Every command in the parts runs against the playground cluster, and `kubectl` already points at it.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
