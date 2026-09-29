# Solution: One Workload Vanished From The Mesh

## Step 1 — Read the absence correctly

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

There is no `DISCONNECTED` row in `proxy-status` — the table is built from the
xDS streams `istiod` currently holds, so a proxy that never connected simply has
no entry. **Absence is the state.**

## Step 2 — Separate the three causes in one command

Count containers:

- `2/2` → there is a sidecar; suspect connectivity to `istiod:15012`.
- `1/1` → there is no sidecar; stop looking at the network.
- every row missing → the control plane; not this case, `tester` is listed.

`notification-service-v1` is `1/1`. That is cause one, and it takes the network
entirely out of the investigation.

## Step 3 — Work the injection checklist

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

The namespace has **no** injection label — neither `istio-injection=enabled` nor
`istio.io/rev`. The pod template is clean, so nothing opted out; the namespace
was simply never selected by the injector webhook.

## Step 4 — Fix the namespace, then recreate the pods

Both halves are required. Injection happens at pod creation only, so a label on
its own changes nothing for pods that already exist:

```sh
kubectl label namespace proxysync-demo istio-injection=enabled
kubectl -n proxysync-demo rollout restart deployment notification-service-v1
kubectl -n proxysync-demo rollout status deployment/notification-service-v1 --timeout=180s
```

Labelling the namespace — rather than patching one pod — is what makes the fix
survive the next replacement, which the task requires.

```sh
astrona submit
```

## Step 5 — Prove it connected, not just restarted

These are two independent claims: a container exists, and that proxy reached
`istiod` and acknowledged configuration.

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

```sh
astrona submit
```

## The cause this environment cannot show

Cause two — a `2/2` pod that cannot reach `istiod` — is normally reproduced with
a `NetworkPolicy` blocking egress except DNS. `manifests/networkpolicy-reference.yaml`
holds that manifest for reference, and it will **not** work here: the default
`kind` CNI (`kindnetd`) does not enforce `NetworkPolicy`, so the object applies
and does nothing.

On a cluster running Calico or Cilium the symptom is exact: the pod runs `2/2`,
its row disappears, traffic continues on cached configuration, and the proxy log
loops on connection failures — which is the diagnostic that works anywhere:

```sh
kubectl -n proxysync-demo logs deploy/notification-service-v1 -c istio-proxy --tail=20 \
  | grep -i -E 'xds|15012|connect'
```

## Common mistakes

- Debugging YAML while the proxy is `STALE` or missing. The config you are
  reading was never applied.
- Treating `NOT SENT` as an error. For `RDS` on a workload with no HTTP routes
  it is expected.
- Forgetting that a missing pod means no sidecar **or** no connectivity — which
  are different fixes.
- Labelling the namespace and not restarting the workload. Nothing changes and
  the fix looks wrong.

## Practice variations

- Scale `istiod` to zero and watch what still works, since proxies keep their
  last config.
- Install a second revision and use `proxy-status` to confirm which workloads
  moved.
- Compare `istioctl proxy-status <pod>.<ns>` output before and after an
  intentional config change.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Sidecar injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) — why a pod came up without a proxy
- [Canary upgrades and revision labels](https://istio.io/latest/docs/setup/upgrade/canary/) — revision labels, and the skew that breaks a data plane
