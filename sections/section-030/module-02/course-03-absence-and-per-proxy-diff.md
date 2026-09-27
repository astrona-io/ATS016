# Part 3 — Absence, And The Per-Proxy Diff

> Prerequisite: [Part 2 — Reading The Table](./course-02-reading-the-proxy-status-table.md). Next: [the module landing page](./course.md), then [module 030-03](../module-03/course.md).

The most misread `proxy-status` output is the one with a workload missing from it. This part explains why absence is a state rather than a gap, works the three causes in order, and then goes one level deeper — comparing what `istiod` believes it sent against what a single proxy actually holds.

## There is no DISCONNECTED row

From [Part 1](./course-01-xds-and-acknowledgement.md): the table is built from the xDS streams `istiod` currently holds. A proxy that never connected, or whose stream dropped, has no entry to print. Nothing in the command's design could show it — `istiod` does not have a list of proxies that *ought* to exist.

So "my pod is not in the list" is not a missing feature. It is a diagnosis with three candidate causes, in order of how often each is the answer:

```text
   1. The pod has no sidecar.            → no Envoy, no stream, no row      (most common)
        check: READY column — 2/2 vs 1/1

   2. The proxy cannot reach istiod.     → sidecar exists, stream fails
        check: istio-proxy log for 15012 connection errors

   3. istiod is not serving.             → every row is missing
        check: kubectl -n istio-system get pods -l app=istiod
```

The check that separates the first two takes no thought at all: **count the containers.** A pod with a sidecar reports `2/2`; one without reports `1/1`. If it is `1/1`, stop looking at the network.

## Making a workload disappear

The fastest way to internalise this is to cause it. Removing the namespace injection label and restarting produces a pod with no sidecar — cause one, on demand.

> [!TIP]
> **Try it — making a workload disappear from the table**
>
> Both changes here are undone in the next checkpoint.
>
> ```sh
> kubectl label namespace proxysync-demo istio-injection-
> kubectl -n proxysync-demo rollout restart deployment notification-service-v1
> kubectl -n proxysync-demo rollout status deployment notification-service-v1 --timeout=120s
> kubectl -n proxysync-demo get pods
> istioctl proxy-status | grep proxysync-demo
> ```
>
> Expect something like:
>
> ```text
> NAME                                       READY   STATUS    RESTARTS   AGE
> notification-service-v1-5f7b9c4d8-nq2wl    1/1     Running   0          20s
> tester-6d9f7b8c5-hj4kz                     2/2     Running   0          9m
>
> tester-6d9f7b8c5-hj4kz.proxysync-demo      Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  ...
> ```
>
> The workload is `Running` and healthy by every Kubernetes measure, and it has left the mesh entirely — `1/1` instead of `2/2`, and no row. `tester` still has its sidecar and is still listed, which is what makes this a per-pod problem rather than a control plane one. That contrast is the discrimination to practise: one missing row is a pod problem, all missing rows is an `istiod` problem.

Restoring it also demonstrates a habit worth keeping: after any change meant to bring a workload back into the mesh, `proxy-status` is the confirmation that it **reconnected**, rather than merely restarted.

> [!TIP]
> **Try it — restoring injection**
>
> ```sh
> kubectl label namespace proxysync-demo istio-injection=enabled
> kubectl -n proxysync-demo rollout restart deployment notification-service-v1
> kubectl -n proxysync-demo rollout status deployment notification-service-v1 --timeout=120s
> istioctl proxy-status | grep proxysync-demo
> ```
>
> Expect something like:
>
> ```text
> notification-service-v1-...proxysync-demo  Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  istiod-7d4c9b8f4-k2m8x  1.30.5
> tester-...proxysync-demo                   Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  istiod-7d4c9b8f4-k2m8x  1.30.5
> ```
>
> The row is back and synced within seconds of the pod becoming ready. Watch the ordering implied here: the proxy connects, receives the full configuration set, ACKs it, and only then does the pod report ready — Istio's readiness probe on the sidecar waits for initial configuration, which is why a control plane outage stops pods becoming ready rather than merely leaving them unconfigured.

## Cause two: a sidecar that cannot reach istiod

This is the case where the pod is `2/2` and the row is still absent. The proxy needs to reach `istiod.istio-system.svc:15012`, and anything on that path can break it:

- a `NetworkPolicy` restricting egress from the workload — commonly introduced by a security team tightening rules, and the most frequent real-world instance;
- a cluster-level firewall or service mesh of the non-Istio kind in front of it;
- a `Sidecar` resource whose `egress` scoping excludes `istio-system`;
- DNS failure resolving the `istiod` Service.

### What this playground cannot show

The canonical reproduction is a `NetworkPolicy` blocking egress except DNS. It **will not work here**: the default `kind` CNI (`kindnetd`) does not enforce `NetworkPolicy`, so the object applies and does nothing at all. That is worth knowing in its own right — a policy that silently does nothing is a failure mode of its own, and one reason to verify enforcement rather than assume it.

On a cluster with a policy-enforcing CNI such as Calico or Cilium, this is the manifest:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-control-plane
  namespace: proxysync-demo
spec:
  podSelector:
    matchLabels:
      app: notification-service
  policyTypes:
    - Egress
  egress:
    - ports:
        - protocol: UDP
          port: 53
```

The symptom there is exact: the pod runs as `2/2`, its row disappears from `proxy-status`, traffic continues on cached configuration, and the `istio-proxy` log loops on connection failures to `istiod.istio-system.svc:15012` — the grep from [Part 1](./course-01-xds-and-acknowledgement.md), which is the diagnostic that works on any cluster.

## Asking about one proxy

When a row is present but `STALE`, the table has told you all it can. `istioctl proxy-status <pod>.<namespace>` goes further: it fetches that proxy's live configuration from its admin interface, fetches what `istiod` believes it sent, and **compares them**.

Underneath it is a diff of two `config_dump`-shaped documents, which is why the output speaks in Envoy's vocabulary rather than Istio's.

> [!TIP]
> **Try it — the per-proxy comparison**
>
> ```sh
> istioctl proxy-status deploy/notification-service-v1.proxysync-demo | head -30
> ```
>
> Expect something like:
>
> ```text
> Clusters Match
> Listeners Match
> Routes Match
> ```
>
> Three "Match" lines is a healthy proxy: `istiod`'s record and the proxy's live configuration are identical. When they are not, the command prints a unified diff of the two documents, and the resource named in the diff is the one that failed to apply — which is usually enough to identify the object that produced it.
>
> Note the target syntax: `deploy/<name>.<namespace>`, or the `<pod>.<namespace>` string exactly as the table's `NAME` column prints it. Both forms work; copying from the table is the reliable one.

Reading a non-matching diff is a short exercise in translation. A cluster named `outbound|80|v3|notification-service...` appearing on one side and not the other points at a `DestinationRule` subset — the naming convention is [section 040](../../section-040/module-01/course.md)'s subject, and it is what turns an Envoy-language diff back into the Istio object you need to edit.

## What to do with each answer

```text
   row present, SYNCED        → configuration arrived. Go to proxy-config (section 040).
   row present, STALE (brief) → wait, re-run.
   row present, STALE (stuck) → look for a NACK: istiod log "reject", pilot_total_xds_rejects.
   row absent, pod 1/1        → no sidecar. Module 030-03.
   row absent, pod 2/2        → connectivity to istiod:15012. Read the istio-proxy log.
   all rows absent            → istiod. Module 030-01.
```

That table is the module in five lines, and it is worth memorising in preference to any individual command's flags.

> [!WARNING]
> **Pitfalls around absence and diffs**
>
> - **Looking for a missing pod's state in the table.** There is no `DISCONNECTED` row; absence *is* the state.
> - **Debugging the network before counting containers.** `1/1` means no sidecar, and no amount of connectivity work will produce a row.
> - **Applying a `NetworkPolicy` and assuming it is enforced.** Some CNIs, including `kind`'s default, ignore them entirely.
> - **Retrying `kubectl apply` at a `STALE` proxy.** Re-applying an object `istiod` already holds changes nothing and does not retry a push.
> - **Reading a per-proxy diff as an Istio object.** It speaks Envoy — cluster and listener names — and needs translating back through the naming convention.
> - **Concluding a workload rejoined the mesh because it restarted.** Restarting produces a pod; only a row in `proxy-status` proves it connected and was configured.

> *Absence from the table is not missing data — it is the most common diagnosis the command makes.*

## Reference

- `istioctl proxy-status <pod>.<namespace> --help` — the per-proxy comparison and its target forms.
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — worked examples of a non-matching diff.
- [Network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) — including the explicit warning that enforcement depends on the CNI plugin.
- [Sidecar resource](https://istio.io/latest/docs/reference/config/networking/sidecar/) — `egress` scoping, and why excluding `istio-system` cuts a proxy off from its control plane.
