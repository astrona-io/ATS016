# Solution: One Workload Vanished From The Mesh

One workload is missing from `istioctl proxy-status`. This walkthrough reads the absence, separates the three causes with one check, fixes the real cause in a way that survives the next pod replacement, and proves the workload connected.

## Step 1: Read the absence correctly

List the proxies for the namespace, and its pods:

```sh
istioctl proxy-status | grep proxysync-demo
kubectl -n proxysync-demo get pods
```

```text
tester-6d9f7b8c5-hj4kz.proxysync-demo     Kubernetes     istiod-7d4c9b8f4-k2m8x     1.30.5     4 (CDS,LDS,EDS,RDS)

NAME                                      READY   STATUS    RESTARTS   AGE
notification-service-v1-5f7b9c4d8-nq2wl   1/1     Running   0          22m
tester-6d9f7b8c5-hj4kz                    2/2     Running   0          31m
```

`istioctl proxy-status` has no `DISCONNECTED` row. The table is built from the xDS streams `istiod` holds right now, so a proxy that never connected simply has no entry. **The absence is the state.**

## Step 2: Separate the three causes with one check

Count the containers in the `READY` column:

- `2/2`: there is a sidecar, so suspect the connection to `istiod` on port `15012`.
- `1/1`: there is no sidecar, so stop looking at the network.
- Every row missing: the control plane. Not this case, because `tester` is listed.

`notification-service-v1` shows `1/1`. That is cause one, and it takes the network out of the investigation.

## Step 3: Check the injection labels

Check the namespace labels, then the pod template labels:

```sh
kubectl get ns proxysync-demo --show-labels
kubectl -n proxysync-demo get deploy notification-service-v1 \
  -o jsonpath='{.spec.template.metadata.labels}{"\n"}'
```

```text
NAME             STATUS   AGE   LABELS
proxysync-demo   Active   34m   kubernetes.io/metadata.name=proxysync-demo

{"app":"notification-service","version":"v1"}
```

The namespace has **no** injection label: neither `istio-injection=enabled` nor `istio.io/rev`. The pod template has no opt-out label either. So the injection webhook was never asked to add a sidecar to this pod.

## Step 4: Label the namespace, then recreate the pods

You need both halves. Injection only happens when a pod is created, so a label on its own changes nothing for pods that already exist:

```sh
kubectl label namespace proxysync-demo istio-injection=enabled
kubectl -n proxysync-demo rollout restart deployment notification-service-v1
kubectl -n proxysync-demo rollout status deployment/notification-service-v1 --timeout=180s
```

Labelling the namespace, instead of patching one pod, is what makes the fix survive the next replacement, as the task requires.

Submit to see your progress:

```sh
astrona submit
```

## Step 5: Prove it connected, not just restarted

These are two separate claims: a sidecar exists in the pod, and that proxy reached `istiod` and confirmed its configuration. Check both, then send a real request:

```sh
kubectl -n proxysync-demo get pods \
  -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name,INIT:.spec.initContainers[*].name'
istioctl proxy-status -v 1 | grep proxysync-demo
kubectl -n proxysync-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

The first command lists the containers and init containers of each pod. The lab's node runs Kubernetes 1.33 or later, so Istio 1.30 runs `istio-proxy` as a Kubernetes native sidecar, an init container with `restartPolicy: Always`: it is missing from the `CONTAINERS` column and appears in the `INIT` column for both pods. The grader checks both lists. The second command should show both pods with `SYNCED` for `CDS`, `EDS`, `LDS` and `RDS`, and the last command should print `200`.

Submit for the final grade:

```sh
astrona submit
```

## The cause this lab does not use

Cause two, a `2/2` pod that cannot reach `istiod`, is usually caused by a `NetworkPolicy` that blocks outgoing traffic except DNS. Whether such a policy takes effect depends on the network plugin. The `kind` network plugin enforces `NetworkPolicy` since `kind` v0.24, and so do Calico and Cilium. Where it is enforced, a new pod behind the policy never gets configuration, never becomes ready, and has no row. The proxy log shows the repeated connection errors, and this search works on any cluster:

```sh
kubectl -n proxysync-demo logs deploy/notification-service-v1 -c istio-proxy --tail=20 \
  | grep -i -E 'xds|15012|connect'
```

## Common mistakes

- Debugging YAML while the proxy is missing or `STALE`. The configuration you are reading never reached it.
- Treating `NOT SENT` as an error. For `RDS` on a workload with no HTTP routes it is expected.
- Forgetting that a missing pod means no sidecar **or** no connection, which need different fixes.
- Labelling the namespace and not restarting the workload. Nothing changes, and the fix looks wrong.

## Practice variations

- Scale `istiod` to zero and watch what still works, since proxies keep their last configuration.
- Install a second revision and use the `ISTIOD` column to confirm which workloads moved.
- Compare `istioctl proxy-status <pod>.<namespace>` before and after a deliberate configuration change.
