# Absence, And The Per-Proxy Diff

The most misread output of `istioctl proxy-status` is the one where a workload is missing. This part explains why a missing row is a diagnosis and not a gap in the data, works through its three causes in order, and then goes one level deeper: comparing what `istiod` sent with what one proxy actually holds.

## There is no DISCONNECTED row

`istioctl proxy-status` is built from the xDS streams `istiod` holds right now. A proxy that never connected, or whose stream dropped, has no entry to print. Nothing in the command could show it, because `istiod` has no list of proxies that *ought* to exist. So "my pod is not in the list" is a diagnosis with three possible causes, listed in order of how often each one is the answer:

| Order | Cause | What it means | How to check |
| --- | --- | --- | --- |
| 1 (most common) | The pod has no sidecar proxy | No proxy, so no stream and no row | The `READY` column: `2/2` or `1/1` |
| 2 | The proxy cannot reach `istiod` | The sidecar exists, but its connection to port `15012` fails | The `istio-proxy` log, for errors against port `15012` |
| 3 | `istiod` is not serving | **Every** row is missing | `kubectl -n istio-system get pods -l app=istiod` |

The check that separates the first two causes is to **count the containers.** A pod with a sidecar shows `2/2` in the `READY` column, and one without shows `1/1`. If it is `1/1`, stop looking at the network.

## Making a workload disappear

The fastest way to learn this is to cause it. Sidecar injection adds the proxy only when a pod is created in a namespace that has an injection label. If you remove the namespace's `istio-injection` label and restart a Deployment, its new pod starts with no sidecar: cause one, on demand.

<!-- astrona:playground:renew -->

Remove the injection label from the namespace, restart the application, and list the pods and the proxies again. You undo both changes in the next step.

```sh
kubectl label namespace proxysync-demo istio-injection-
kubectl -n proxysync-demo rollout restart deployment notification-service-v1
kubectl -n proxysync-demo rollout status deployment notification-service-v1 --timeout=120s
kubectl -n proxysync-demo get pods
istioctl proxy-status | grep proxysync-demo
```

You should see something like this (the `Waiting for deployment` lines are left out):

```text
namespace/proxysync-demo unlabeled
deployment.apps/notification-service-v1 restarted
deployment "notification-service-v1" successfully rolled out
NAME                                       READY   STATUS        RESTARTS   AGE
notification-service-v1-54dd46d4b6-b8q8n   2/2     Terminating   0          14s
notification-service-v1-79bc4d85d8-4pfnc   1/1     Running       0          1s
tester-69699fd775-tb6pc                    2/2     Running       0          14s
tester-69699fd775-tb6pc.proxysync-demo                 Kubernetes     istiod-7dc9684c55-jmkrp     1.30.5      4 (CDS,LDS,EDS,RDS)
```

The old pod, `2/2 Terminating`, is still shutting down; it disappears a few seconds later. The new application pod is `Running` and healthy by every Kubernetes measure, and it has left the mesh: `1/1` instead of `2/2`, and no row. `tester` still has its sidecar and is still listed, so this is a problem with one pod, not with the control plane. That is the comparison to practise: one missing row is a pod problem, and every row missing is an `istiod` problem.

Now put the label back and restart again. After any change meant to bring a workload into the mesh, a row in `istioctl proxy-status` is your proof that it **connected**, not just restarted.

```sh
kubectl label namespace proxysync-demo istio-injection=enabled
kubectl -n proxysync-demo rollout restart deployment notification-service-v1
kubectl -n proxysync-demo rollout status deployment notification-service-v1 --timeout=120s
istioctl proxy-status -v 1 | grep proxysync-demo
```

You should see something like:

```text
namespace/proxysync-demo labeled
deployment.apps/notification-service-v1 restarted
deployment "notification-service-v1" successfully rolled out
notification-service-v1-bb5484c79-qpsjj.proxysync-demo     Kubernetes     SYNCED (0s)      IGNORED     SYNCED (0s)     SYNCED (0s)      SYNCED (0s)      istiod-7dc9684c55-jmkrp     1.30.5
tester-69699fd775-tb6pc.proxysync-demo                     Kubernetes     SYNCED (10s)     IGNORED     SYNCED (0s)     SYNCED (10s)     SYNCED (10s)     istiod-7dc9684c55-jmkrp     1.30.5
```

The `Waiting for deployment` lines are left out here too.

The row is back, and `SYNCED`, within seconds of the pod becoming ready. The order matters here. The proxy connects, receives its configuration and confirms it, and only then does the pod report ready, because the sidecar's readiness check waits for the first configuration. That is why a control plane outage stops new pods from becoming ready, instead of leaving them ready with no configuration.

## Cause two: a sidecar that cannot reach istiod

In the second case the pod is `2/2` and its row is still missing. The proxy must reach `istiod.istio-system.svc:15012`, and anything on that path can break the connection. The most common real case is a Kubernetes `NetworkPolicy` that limits outgoing traffic from the workload, added by a team that tightens network rules. A `NetworkPolicy` is a Kubernetes resource that allows or blocks traffic to and from pods, and the cluster's network plugin enforces it. Other causes are a firewall in front of `istiod`, an Istio `Sidecar` resource whose `egress` list leaves out `istio-system`, and a DNS failure when the proxy looks up the `istiod` Service.

For example, a `NetworkPolicy` that selects the pods with `app: notification-service`, sets `policyTypes: [Egress]`, and allows only UDP port `53` lets those pods send DNS queries and nothing else. Their proxies can then no longer reach `istiod` on port `15012`.

A policy only works if the network plugin enforces it. The `kind` network plugin, `kindnetd`, enforces `NetworkPolicy` since `kind` v0.24, and plugins such as Calico and Cilium do too; some older or simpler plugins accept the object and ignore it. On a cluster that enforces it, a new pod behind this policy starts its sidecar, but the proxy never gets configuration, so the pod never becomes ready and has no row in `istioctl proxy-status`. Searching the proxy log for `xds`, `15012` or `connect` shows the repeated connection errors, and that check works on any cluster.

## Asking about one proxy

When a row is present but stays `STALE` or shows `ERROR`, the table has told you all it can. `istioctl proxy-status <pod>.<namespace>` goes further. It fetches that proxy's live configuration from its administration interface, fetches what `istiod` believes it sent, and **compares them**. Underneath, it compares two configuration dumps in Envoy's format, which is why the output uses Envoy's terms, not Istio's.

Ask for the comparison for the application's proxy:

```sh
istioctl proxy-status deploy/notification-service-v1.proxysync-demo | head -30
```

You should see something like:

```text
Clusters Match
Listeners Match
Routes Match (RDS last loaded at Sat, 10 Oct 2026 00:19:38 CEST)
```

The `Routes Match` line also shows when the routes were last loaded. Three `Match` lines mean a healthy proxy: `istiod`'s record and the proxy's live configuration are identical. When they differ, the command prints `Don't Match` and a diff of the two documents. The resource named in the diff is the one that failed to apply, which is usually enough to find the Istio object behind it. The target can be written as `deploy/<name>.<namespace>`, or as the `<pod>.<namespace>` string exactly as the `NAME` column prints it.

Reading a diff means translating Envoy names back to Istio objects. A cluster named `outbound|80|v3|notification-service.proxysync-demo.svc.cluster.local` on one side and not the other points at a `DestinationRule` subset called `v3`. The cluster name gives you the direction, the port, the subset and the host, and that tells you which Istio object to edit.

## What to do with each answer

The whole module fits in one table:

| What you see | What it means | Next step |
| --- | --- | --- |
| Row present, `SYNCED` | The configuration arrived | Read what the proxy does with it, with `istioctl proxy-config` |
| Row present, `STALE` for a moment | The protocol at work | Wait and run it again |
| Row present, `STALE` for a long time | The proxy is slow or its connection is poor | Check the proxy's resources and log |
| Row present, `ERROR` | The proxy sent a NACK | Look for `reject` in the `istiod` log and for `pilot_total_xds_rejects` |
| Row missing, pod `1/1` | No sidecar | Find out why injection did not happen |
| Row missing, pod `2/2` | No connection to `istiod` on port `15012` | Read the `istio-proxy` log |
| Every row missing | `istiod` is not serving | Check the control plane |

You can now read a missing row and tell its three causes apart, starting with a count of the containers. You know how to prove a workload connected, not just restarted, and how to compare one proxy's live configuration with what `istiod` sent. The cause that this module only described, a pod with no sidecar, has its own checklist, which starts with the injection labels.

## Common pitfalls

> [!WARNING]
> - **Looking for a missing pod's state in the table.** There is no `DISCONNECTED` row; the absence *is* the state.
> - **Debugging the network before counting containers.** `1/1` means no sidecar, and no network fix will produce a row.
> - **Assuming a `NetworkPolicy` is enforced, or that it is not.** It depends on the network plugin. Check the plugin before you trust or dismiss a policy.
> - **Applying an object again for a `STALE` or `ERROR` proxy.** The same content changes nothing and does not retry a push.
> - **Reading a per-proxy diff as an Istio object.** It uses Envoy's cluster and listener names, and must be translated back.
> - **Deciding a workload rejoined the mesh because it restarted.** A restart produces a pod; only a row in `istioctl proxy-status` proves it connected and got its configuration.

## Your mission: One Workload Vanished From The Mesh

You can now read a missing row, tell its three causes apart, and prove a workload reconnected. The graded lab gives you a namespace where one workload has dropped out of `istioctl proxy-status`, and asks you to find out why and bring it back in a way that survives the next pod replacement.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-030-02
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-02/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-030/module-02/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-030-02
astrona start ats-016-playground-030-02
```
