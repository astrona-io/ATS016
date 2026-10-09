# Summary

When a change does nothing, either the configuration is wrong or it never reached the proxy. `istioctl proxy-status` tells you which, and this module showed how to read it and what it cannot show.

## What you learned

The sidecar proxy does not read Kubernetes. `pilot-agent`, inside the `istio-proxy` container, opens one gRPC stream to `istiod` on port `15012` and relays xDS configuration to Envoy. `istiod` pushes four main resource types over that stream: `LDS` for listeners, `RDS` for routes, `CDS` for clusters and `EDS` for endpoints. A request uses them in that order. The proxy answers every push with an ACK, or with a NACK that keeps its previous configuration running. So a rejected change does not break traffic; it simply never takes effect.

`istioctl proxy-status` is built from these answers. The short form lists each connected proxy with its `istiod` pod, its version and the xDS types it asked for. Since Istio 1.27, the sync state of each type needs `istioctl proxy-status -v 1`. `SYNCED` means the proxy confirmed the latest push, `STALE` means an ACK is still missing, `ERROR` means the proxy sent a NACK, and `NOT SENT` means there was nothing to send. `SYNCED` proves delivery, never correctness. The `ISTIOD` column proves which revision serves a workload, and the `VERSION` column shows skew: the control plane may be one minor version ahead of the data plane, never behind it.

A missing row is a diagnosis, not missing data. The table is built from live streams, so it has no disconnected state. The three causes, in order, are no sidecar, no connection to `istiod`, and no control plane. `istioctl proxy-status <pod>.<namespace>` compares one proxy's live configuration with what `istiod` sent. The key facts to remember are these:

- Count the containers first: `1/1` means no sidecar, so the network is not the problem.
- One missing row is a pod problem; every row missing is an `istiod` problem.
- A restart is not proof that a workload joined the mesh; a `SYNCED` row is.
- Whether a `NetworkPolicy` blocks port `15012` depends on the network plugin enforcing it.

<!-- astrona:playground:destroy -->
