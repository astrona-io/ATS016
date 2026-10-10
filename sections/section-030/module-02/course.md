# Diagnose Configuration Sync With proxy-status

You applied a `VirtualService`, the Istio resource that tells the sidecar proxies how to route requests for a host. `istioctl analyze` reports no problems, the object is in the cluster, and requests still go to the wrong place. At that point there are exactly two possibilities, and they need different fixes: either the configuration is wrong, or it never reached the proxy.

`istioctl proxy-status` tells you which, in a few seconds. It lists every sidecar proxy connected to `istiod`, Istio's control plane, and with `-v 1` it shows whether each proxy has confirmed the latest configuration for each resource type. A sidecar proxy (Envoy) is a proxy container that Istio adds to each pod; all inbound and outbound traffic of the pod passes through it.

The command only prints a table. What makes the table trustworthy is the protocol underneath it: every piece of configuration `istiod` sends must be answered with an ACK (accepted) or a NACK (rejected). This module has three parts. **How Configuration Reaches A Proxy** explains that protocol, xDS, and its acknowledgements. **Reading The Table** reads `istioctl proxy-status` column by column and explains each state. **Absence, And The Per-Proxy Diff** covers a proxy that is missing from the table, its three causes, and how to compare one proxy with what `istiod` sent. A graded lab follows the third part.

## Learning objectives

After this module you can:

- Describe the xDS stream between a proxy and `istiod`, including which side opens it and on which port.
- Name the four main xDS resource types, say what each carries, and explain how they fit together into a request path.
- Explain what an ACK and a NACK are, and how they make `istioctl proxy-status` possible.
- Read `istioctl proxy-status` and `istioctl proxy-status -v 1`, and say what each column reports.
- Tell `SYNCED`, `STALE`, `NOT SENT` and `ERROR` apart, and say what each one rules in or out.
- Explain what `SYNCED` does *not* prove.
- Use the output to spot version skew and to confirm which `istiod` pod serves a workload.
- Explain what it means when a workload is missing from the output, and check the three causes in order.
- Run `istioctl proxy-status` against one proxy to compare what `istiod` sent with what the proxy holds.

## Before you start

You need Kubernetes basics: `kubectl` to list pods, read logs and change labels. You also need to know that `istiod` pushes configuration to every proxy, and that each proxy keeps the last configuration it was given.

Your playground is a single-node `kind` cluster with **Istio 1.30.5** installed with the `demo` profile, and `istioctl` on your PATH. The namespace **`proxysync-demo`** has sidecar injection switched on and runs these workloads:

| Workload | What it is |
| --- | --- |
| `notification-service-v1` | A Deployment behind the Service `notification-service` on port `80`. It answers `["EMAIL"]` |
| `tester` | A client pod with `curl`. Every test request in this module is sent from here |

Everything starts healthy, and every proxy starts `SYNCED`. Making one disappear from the table is up to you.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->
