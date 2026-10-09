# Absence, And The Per-Proxy Diff

Astronaut, the most misread roll call is the one where a ship is missing. This part explains why a missing row is a diagnosis and not a gap, works through the three causes in order, and then goes one level deeper: comparing what `istiod` thinks it sent with what one proxy actually holds.

## There is no DISCONNECTED row

`istioctl proxy-status` is built from the xDS streams `istiod` holds right now. A proxy that never connected, or whose stream dropped, has no entry to print. Nothing in the command could show it, because `istiod` has no list of proxies that *ought* to exist.

So "my pod is not in the list" is not a missing feature. It is a diagnosis with three possible causes, in order of how often each is the answer:

| Order | Cause | What it means | How to check |
| --- | --- | --- | --- |
| 1 (most common) | The pod has no sidecar | No communications officer, so no stream and no row | The `READY` column: `2/2` or `1/1` |
| 2 | The proxy cannot reach `istiod` | The officer is on board, but the radio link fails | The `istio-proxy` log, for errors against port `15012` |
| 3 | `istiod` is not serving | **Every** row is missing | `kubectl -n istio-system get pods -l app=istiod` |

The check that separates the first two takes no thought at all: **count the containers.** A pod with a sidecar shows `2/2`, and one without shows `1/1`. If it is `1/1`, stop looking at the network.

## Making a workload disappear

The fastest way to learn this is to cause it. If you remove the planet's injection label and restart a Deployment, its new pod launches with no communications officer: cause one, on demand.

<!-- astrona:playground:renew -->

### Remove a ship from the roll call

Remove the namespace's injection label, restart the app, and take the roll call again. You undo both changes in the next step.

```sh
kubectl label namespace proxysync-demo istio-injection-
kubectl -n proxysync-demo rollout restart deployment notification-service-v1
kubectl -n proxysync-demo rollout status deployment notification-service-v1 --timeout=120s
kubectl -n proxysync-demo get pods
istioctl proxy-status | grep proxysync-demo
```

You should see something like:

```text
NAME                                       READY   STATUS    RESTARTS   AGE
notification-service-v1-5f7b9c4d8-nq2wl    1/1     Running   0          20s
tester-6d9f7b8c5-hj4kz                     2/2     Running   0          9m

tester-6d9f7b8c5-hj4kz.proxysync-demo      Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  ...
```

The app is `Running` and healthy by every Kubernetes measure, and it has left the mesh: `1/1` instead of `2/2`, and no row. `tester` still has its sidecar and is still listed, which makes this a problem with one pod, not with the control plane. That is the comparison to practise: one missing row is a pod problem, all missing rows is an `istiod` problem.

### Bring the ship back

Put the label back and restart again. After any change meant to bring a workload into the mesh, `istioctl proxy-status` is your proof that it **reconnected**, not just restarted.

```sh
kubectl label namespace proxysync-demo istio-injection=enabled
kubectl -n proxysync-demo rollout restart deployment notification-service-v1
kubectl -n proxysync-demo rollout status deployment notification-service-v1 --timeout=120s
istioctl proxy-status | grep proxysync-demo
```

You should see something like:

```text
notification-service-v1-...proxysync-demo  Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  istiod-7d4c9b8f4-k2m8x  1.30.5
tester-...proxysync-demo                   Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  istiod-7d4c9b8f4-k2m8x  1.30.5
```

The row is back, and `SYNCED`, within seconds of the pod becoming ready. The order matters here. The proxy connects, receives its full orders, confirms them, and only then does the pod report ready, because the sidecar's readiness check waits for the first configuration. That is why a control plane outage stops new pods from becoming ready, instead of leaving them ready without orders.

## Cause two: a sidecar that cannot reach istiod

This is the case where the pod is `2/2` and its row is still missing. The proxy must reach `istiod.istio-system.svc:15012`, and anything on that path can break the link:

- A `NetworkPolicy` that limits outgoing traffic from the workload. A security team tightening rules often adds one, and it is the most common real-world case.
- A firewall in the cluster, in front of `istiod`.
- An Istio `Sidecar` resource whose `egress` list leaves out `istio-system`.
- A DNS failure when the proxy looks up the `istiod` Service.

### What this playground cannot show

The usual way to reproduce this is a `NetworkPolicy` that blocks all outgoing traffic except DNS. It **does not work here**. The default `kind` network plugin (`kindnetd`) does not enforce `NetworkPolicy`, so the object is accepted and does nothing at all. That is worth knowing on its own: a policy that silently does nothing is a failure of its own, and a reason to check that policies are enforced instead of assuming it.

On a cluster with a network plugin that enforces policies, such as Calico or Cilium, you would save this as `networkpolicy-block-control-plane.yaml` and apply it with `kubectl apply -f networkpolicy-block-control-plane.yaml`:

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

There, the symptom is exact. The pod runs as `2/2`, its row disappears from `istioctl proxy-status`, traffic continues on stored orders, and the `istio-proxy` log repeats connection failures to `istiod.istio-system.svc:15012`. Searching the proxy log for `xds`, `15012` or `connect` is the check that works on any cluster.

## Asking about one proxy

When a row is present but `STALE`, the table has told you all it can. `istioctl proxy-status <pod>.<namespace>` goes further. It fetches that proxy's live configuration from its administration page, fetches what `istiod` believes it sent, and **compares them**.

Underneath, it compares two configuration dumps in Envoy's format. That is why the output speaks Envoy's language, not Istio's.

### Compare one proxy with mission control's record

Ask for the comparison for the app's proxy:

```sh
istioctl proxy-status deploy/notification-service-v1.proxysync-demo | head -30
```

You should see something like:

```text
Clusters Match
Listeners Match
Routes Match
```

Three `Match` lines mean a healthy proxy: `istiod`'s record and the proxy's live configuration are identical. When they differ, the command prints a diff of the two documents. The resource named in the diff is the one that failed to apply, which is usually enough to find the Istio object behind it.

The target can be written as `deploy/<name>.<namespace>`, or as the `<pod>.<namespace>` string exactly as the table's `NAME` column prints it. Both work; copying from the table is the safest.

Reading a diff that does not match is a small translation exercise. A cluster named `outbound|80|v3|notification-service...` on one side and not the other points at a `DestinationRule` subset called `v3`. The cluster name gives you the direction, the port, the subset and the host, and that tells you which Istio object to edit.

## What to do with each answer

The whole module fits in one table. It is worth remembering better than any single command's flags.

| What you see | What it means | Next step |
| --- | --- | --- |
| Row present, `SYNCED` | The configuration arrived | Read what the proxy does with it, with `istioctl proxy-config` |
| Row present, `STALE` for a moment | The protocol at work | Wait and run it again |
| Row present, `STALE` and stuck | Probably a NACK | Look for `reject` in the `istiod` log and for `pilot_total_xds_rejects` |
| Row missing, pod `1/1` | No sidecar | Find out why injection did not happen |
| Row missing, pod `2/2` | No link to `istiod` on port `15012` | Read the `istio-proxy` log |
| Every row missing | `istiod` is not serving | Check the control plane |

## Common pitfalls

> [!WARNING]
> - **Looking for a missing pod's state in the table.** There is no `DISCONNECTED` row; the absence *is* the state.
> - **Debugging the network before counting containers.** `1/1` means no sidecar, and no amount of network work will produce a row.
> - **Applying a `NetworkPolicy` and assuming it is enforced.** Some network plugins, including `kind`'s default, ignore them completely.
> - **Re-applying an object for a `STALE` proxy.** Re-applying something `istiod` already holds changes nothing and does not retry a push.
> - **Reading a per-proxy diff as an Istio object.** It speaks Envoy, in cluster and listener names, and must be translated back.
> - **Deciding a workload rejoined the mesh because it restarted.** A restart produces a pod; only a row in `istioctl proxy-status` proves it connected and got its orders.

> *A ship missing from the roll call is not missing data: it is the most common diagnosis the command makes.*

## Your mission: One Workload Vanished From The Mesh

You can now read a missing row, tell its three causes apart, and prove a workload reconnected. Now prove it in a graded mission: one workload in `proxysync-demo` has dropped off the roll call, and you have to find out why and bring it back for good.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-030-02
```

Then start the mission:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-02/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-030/module-02/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-016-lab-030-02
astrona start ats-016-playground-030-02
```
