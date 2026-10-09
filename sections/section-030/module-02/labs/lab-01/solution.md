# Solution: One Workload Vanished From The Mesh

Astronaut, a ship is missing from the roll call. This walkthrough reads the absence, separates the three causes with one check, fixes the real cause in a way that survives the next pod replacement, and proves the ship reconnected.

## Step 1: Read the absence correctly

Take the roll call for the namespace, and list its pods:

```sh
istioctl proxy-status | grep proxysync-demo
kubectl -n proxysync-demo get pods
```

```text
tester-6d9f7b8c5-hj4kz.proxysync-demo   Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  ...

NAME                                      READY   STATUS    RESTARTS   AGE
notification-service-v1-5f7b9c4d8-nq2wl   1/1     Running   0          22m
tester-6d9f7b8c5-hj4kz                    2/2     Running   0          31m
```

`istioctl proxy-status` has no `DISCONNECTED` row. The table is built from the xDS streams `istiod` holds right now, so a proxy that never connected simply has no entry. **The absence is the state.**

## Step 2: Separate the three causes with one check

Count the containers:

- `2/2`: there is a sidecar, so suspect the connection to `istiod` on port `15012`.
- `1/1`: there is no sidecar, so stop looking at the network.
- Every row missing: the control plane. Not this case, because `tester` is listed.

`notification-service-v1` shows `1/1`. That is cause one, and it takes the network out of the investigation completely.

## Step 3: Work the injection checklist

Check the planet's labels, then the pod template's labels:

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

The namespace has **no** injection label: neither `istio-injection=enabled` nor `istio.io/rev`. The pod template is clean, so nothing opted out. The injection webhook (the launch-pad crew) was simply never asked to put a communications officer on this ship.

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

These are two separate claims: a sidecar exists in the pod, and that proxy reached `istiod` and confirmed its orders. Check both, then send a real signal:

```sh
kubectl -n proxysync-demo get pods \
  -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
istioctl proxy-status | grep proxysync-demo
kubectl -n proxysync-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

```text
notification-service-v1-...   notification-service,istio-proxy
tester-...                    tester,istio-proxy

notification-service-v1-...proxysync-demo  Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  ...
tester-...proxysync-demo                   Kubernetes  SYNCED  SYNCED  SYNCED  SYNCED  ...
200
```

On Kubernetes 1.28 and later, the proxy can run as a native sidecar, listed under `initContainers` instead of `containers`. If `istio-proxy` is missing from the `CONTAINERS` column, look there before you conclude anything; the grader checks both lists.

Submit for the final grade:

```sh
astrona submit
```

## The cause this environment cannot show

Cause two, a `2/2` pod that cannot reach `istiod`, is usually reproduced with a `NetworkPolicy` that blocks all outgoing traffic except DNS. `manifests/networkpolicy-reference.yaml` holds that manifest for reference, and it does **not** work here. The default `kind` network plugin (`kindnetd`) does not enforce `NetworkPolicy`, so the object is accepted and does nothing.

On a cluster running Calico or Cilium the symptom is exact. The pod runs `2/2`, its row disappears, traffic continues on stored orders, and the proxy log repeats connection failures. This search is the check that works anywhere:

```sh
kubectl -n proxysync-demo logs deploy/notification-service-v1 -c istio-proxy --tail=20 \
  | grep -i -E 'xds|15012|connect'
```

## Common mistakes

- Debugging YAML while the proxy is `STALE` or missing. The configuration you are reading never reached it.
- Treating `NOT SENT` as an error. For `RDS` on a workload with no HTTP routes it is expected.
- Forgetting that a missing pod means no sidecar **or** no connection, which need different fixes.
- Labelling the namespace and not restarting the workload. Nothing changes, and the fix looks wrong.

## Practice variations

- Scale `istiod` to zero and watch what still works, since proxies keep their last orders.
- Install a second revision and use `istioctl proxy-status` to confirm which workloads moved.
- Compare `istioctl proxy-status <pod>.<namespace>` before and after a deliberate configuration change.
