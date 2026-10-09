# Fix It And Prove It Joined

In the playground the checklist stops at step 2: `reporting-service` carries `sidecar.istio.io/inject: "false"` on its pod template. Finding the cause is only half of the work. This part removes that opt-out, proves from two independent directions that the workload joined the mesh, and checks that it still answers requests.

## Removing the opt-out

The fix has two halves. Removing the label changes the pod template, and only a new pod goes through the injection webhook. Here, one command does both. The label key contains a `/`, and in a JSON Patch the `/` separates the parts of the path, so the key must be written with `~1` in place of the `/`. That is the one unusual detail in this command.

<!-- astrona:playground:renew -->

Remove the label from the pod template and wait for the rollout:

```sh
kubectl -n noinject-demo patch deployment reporting-service --type json \
  -p '[{"op":"remove","path":"/spec/template/metadata/labels/sidecar.istio.io~1inject"}]'
kubectl -n noinject-demo rollout status deployment reporting-service --timeout=120s
```

You should see something like:

```text
deployment.apps/reporting-service patched
deployment "reporting-service" successfully rolled out
```

Changing the **pod template** changes its hash, so the Deployment controller creates a new ReplicaSet and therefore new pods. No separate restart was needed. If the fix had been a *namespace* label instead, no pod would have been recreated, and `kubectl rollout restart` would have been the necessary second step. A pod-template fix recreates pods by itself; a namespace label, webhook or revision fix does not.

## Proving it joined

Confirm from two directions, because they are two separate claims. The container list says a proxy exists in the pod. `istioctl proxy-status -v 1` says that the proxy connected to `istiod` and confirmed its configuration. A pod can pass the first check and fail the second, for example when something blocks its connection to `istiod` on port `15012`. Print the new pod's containers, then look for the workload in the proxy list:

```sh
kubectl -n noinject-demo get pods -l app=reporting-service \
  -o jsonpath='{.items[0].spec.containers[*].name}{"\n"}'
istioctl proxy-status -v 1 | grep reporting-service
```

You should see something like:

```text
reporting-service istio-proxy
reporting-service-5c7d9f684-qv8rz.noinject-demo   Kubernetes   SYNCED (30s)   IGNORED   SYNCED (30s)   SYNCED (30s)   SYNCED (30s)   istiod-7d4c9b8f4-k2m8x   1.30.5
```

The pod has two containers and a `SYNCED` row. The workload is now covered by every mesh policy in this namespace, which was quietly untrue a few minutes ago. If the proxy runs as a native sidecar, which Istio 1.30 does when every node runs Kubernetes 1.33 or later, `istio-proxy` is listed under `initContainers` instead. If the first command prints only `reporting-service`, read `.spec.initContainers[*].name` before you conclude anything.

## Traffic still flows

One more check is needed, and it matters. Joining the mesh means the workload's traffic is now intercepted, and interception is where two hidden problems appear. One is a Service port with no protocol name. The other is an application that listens only on `127.0.0.1`. Both work without a sidecar and break the moment one arrives. Send a request from the `tester` pod to the newly meshed Service, then run the analyzer:

```sh
kubectl -n noinject-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://reporting-service/
istioctl analyze -n noinject-demo
```

You should see something like:

```text
200
✔ No validation issues found when analyzing namespace: noinject-demo.
```

The `200` proves the interception did not break the application, and the analyzer confirms the namespace configuration is coherent. If the request had failed with a connection error instead, the likely cause would be an application that listens only on its loopback address. That is a real and frequent result of joining the mesh, and not a reason to leave the workload outside it.

> [!TIP]
> After bringing any workload into the mesh, finish with three checks: the sidecar is in the pod, the row is `SYNCED` in `istioctl proxy-status -v 1`, and a real request still returns `200`.

You can now bring an excluded workload into the mesh and prove it in three independent ways: the container list, a `SYNCED` row from `istiod`, and a request that still succeeds. Together with the checklist, that covers every reason a pod can start without a sidecar.

## Common pitfalls

> [!WARNING]
> - **Writing the JSON Patch path with a plain `/` in the label key.** The key `sidecar.istio.io/inject` must be written `sidecar.istio.io~1inject`, or the patch targets the wrong path.
> - **Adding a `rollout restart` out of habit and thinking it was needed.** A pod-template change already creates new pods; a namespace label change is the one that needs the restart.
> - **Stopping at "the sidecar is there".** A container that exists is not a proxy that connected. Confirm with `istioctl proxy-status -v 1`.
> - **Assuming interception changes nothing.** A newly meshed workload with an unnamed Service port or a loopback-only listener breaks at exactly the moment it joins.

## Your mission: Bring An Exempt Workload Back Into The Mesh

You can now work the injection checklist, remove a pod-template opt-out, and prove a workload joined the mesh. The graded lab gives you one workload outside the mesh in a correctly labelled namespace, and asks you to bring it in without touching the namespace labels.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-030-03
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-030/module-03/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-030/module-03/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-030-03
astrona start ats-016-playground-030-03
```
