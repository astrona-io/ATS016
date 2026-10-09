# Take The Control Plane Away

Reading about a control plane outage is not the same as seeing one. In this part you scale `istiod` to zero on purpose and watch which half of the mesh notices. Pods that are already running carry on. Anything new, such as a fresh pod, cannot be created. Then you bring `istiod` back and see that nothing was lost, only delayed.

## The validation webhook, working

Start with the case that behaves well. When you apply an Istio object, the Kubernetes API server calls the validating admission webhook `validation.istio.io` and waits while `istiod` checks the object. If the object is clearly invalid, `istiod` refuses it at once. The `VirtualService` below sends traffic for the `notification-service` Service to two destinations with a weight of 60 each, so the weights add up to 120, which is impossible.

<!-- astrona:playground:renew -->

Save this as `virtualservice-bad-weights.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bad-weights
  namespace: cphealth-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
          weight: 60
        - destination:
            host: notification-service
          weight: 60
```

Apply it:

```sh
kubectl apply -f virtualservice-bad-weights.yaml
```

You should see something like:

```text
Error from server: error when creating "STDIN": admission webhook "validation.istio.io" denied the request:
configuration is invalid: total destination weight 120 != 100
```

This output was captured with the YAML sent on standard input, so it says `"STDIN"`. When you apply the file, your file name appears there instead. The message names the component that refused the object: `admission webhook "validation.istio.io"`, which is `istiod`, called by the API server during your write. Everything needed to judge the object was inside the object, so `istiod` decided at once, and the object was never stored. Keep this exchange in mind, because next you remove one side of it.

## Taking the control plane away

Now scale `istiod` down to zero pods.

> [!WARNING]
> This step stops `istiod`. In this playground it is harmless, and you undo it at the end. On a shared cluster it stops sidecar injection, certificate issuing and every configuration change for everyone, and it starts the clock that breaks mutual TLS when the certificates expire. Never run it there to test a theory.

Stop `istiod`, wait until its pod is gone, and send a request from the `tester` pod to the `notification-service` Service:

```sh
kubectl -n istio-system scale deploy istiod --replicas=0
kubectl -n istio-system rollout status deploy istiod --timeout=60s
kubectl -n cphealth-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'existing traffic: %{http_code}\n' -X POST http://notification-service/notify
```

You should see something like:

```text
deployment.apps/istiod scaled
deployment "istiod" successfully rolled out
existing traffic: 200
```

The control plane is gone, and the request still succeeded. Each sidecar proxy routes with the configuration it already holds, and the mutual TLS handshake uses certificates that were already issued. This is why control plane outages are easy to miss and expensive to leave running.

## What stops, and why it stops that way

Existing traffic is only half the picture. The other half is anything that must be **new**: a new pod, a changed route, a renewed certificate. Restarting a Deployment tests the first one at once. Restart the Deployment of the application, then look at the pods and at the events on its ReplicaSet:

```sh
kubectl -n cphealth-demo rollout restart deployment notification-service-v1
kubectl -n cphealth-demo get pods
kubectl -n cphealth-demo describe replicaset -l app=notification-service | tail -15
```

You should see something like:

```text
NAME                                      READY   STATUS    RESTARTS   AGE
notification-service-v1-6c9f8b7d5-x2kqp   2/2     Running   0          14m

  Warning  FailedCreate  ... Error creating: Internal error occurred: failed calling webhook
  "sidecar-injector.istio.io": failed to call webhook: ... connection refused
```

The old pod is still `Running` and still answering; that was the `200` you just saw. The new pod was **never created at all**. The event explains why. The ReplicaSet controller asked the API server to create the pod. The API server tried to call the injection webhook `sidecar-injector.istio.io`, could not reach it, and the webhook's `failurePolicy: Fail` turned that into a refusal of the whole pod. A write of any Istio object fails in the same way now, because the validation webhook also has `failurePolicy: Fail` once `istiod` has started.

The `failurePolicy` is a real design choice with two defensible answers, and Istio's default for injection is the safer one:

| `failurePolicy` | During an `istiod` outage | Trade-off |
| --- | --- | --- |
| `Fail` (Istio default) | Pod creation is refused. Nothing new starts. | Loud. It blocks deployments, possibly including the one that would fix `istiod`. |
| `Ignore` | Pods start **without a sidecar proxy**, outside the mesh | Quiet. Deployments succeed and produce pods with no sidecar, so no mesh policy applies to them. |

`Ignore` is the more dangerous of the two, because it looks like success. A rollout completes, pods show `1/1 Running`, and every `AuthorizationPolicy` and `PeerAuthentication` in that namespace does nothing for those pods. Read the setting on your own cluster once, so it is not abstract:

```sh
kubectl get mutatingwebhookconfiguration istio-sidecar-injector \
  -o jsonpath='{.webhooks[0].failurePolicy}{"\n"}'
```

The command prints `Fail`, the value Istio installs for the injection webhook.

## Recovery needs nothing but the control plane back

Bring `istiod` back and watch the mesh catch up by itself. Scale it up, wait for it and for the application, then list the proxies with `istioctl proxy-status -v 1`, which shows every proxy connected to `istiod` and, for each type of configuration, whether the proxy confirmed the latest version:

```sh
kubectl -n istio-system scale deploy istiod --replicas=1
kubectl -n istio-system rollout status deploy istiod --timeout=120s
kubectl -n cphealth-demo rollout status deployment notification-service-v1 --timeout=120s
istioctl proxy-status -v 1
```

You should see something like this (the gateway rows are left out):

```text
deployment "istiod" successfully rolled out
deployment "notification-service-v1" successfully rolled out
NAME                                       CLUSTER      CDS            ECDS      EDS            LDS            RDS            ISTIOD                     VERSION
notification-service-v1-...cphealth-demo   Kubernetes   SYNCED (20s)   IGNORED   SYNCED (20s)   SYNCED (20s)   SYNCED (20s)   istiod-7d4c9b8f4-k2m8x     1.30.5
tester-...cphealth-demo                    Kubernetes   SYNCED (20s)   IGNORED   SYNCED (20s)   SYNCED (20s)   SYNCED (20s)   istiod-7d4c9b8f4-k2m8x     1.30.5
```

You did not apply anything again. The ReplicaSet controller kept retrying the pod creation. This time the webhook answered, the sidecar was injected, and the proxies reconnected on their own. `SYNCED` in every used column means each proxy confirmed the latest configuration `istiod` sent. `IGNORED` only means the proxy never asked for that type.

Nothing was lost, only delayed. That is the right expectation for any pure control plane outage. If something *does* need to be applied again afterwards, the outage was not the whole story.

> [!TIP]
> After any control plane incident, check `RESTARTS` and run `istioctl proxy-status -v 1`. If every proxy is listed and `SYNCED`, the mesh has caught up by itself.

You have now seen both halves of an outage. Running pods kept serving requests with stored configuration and certificates, while new pods were refused because the injection webhook could not be reached. Scaling `istiod` back up was the whole fix. One case is still open: an object that the cluster stored even though it was invalid, and that `istiod` never sends.

## Common pitfalls

> [!WARNING]
> - **Reading working traffic as a healthy control plane.** During the outage the request still returned `200`. Only something new, such as a pod restart, shows the problem.
> - **Setting the injection webhook to `Ignore` to unblock deployments.** It turns a loud failure into pods quietly outside the mesh, which is the more expensive problem.
> - **Restarting workloads while `istiod` is down.** The new pods cannot be created, and the old ones keep running.
> - **Applying everything again after recovery.** A pure outage loses nothing. If applying again seems needed, look for a second cause.
> - **Scaling `istiod` on a shared cluster to test a theory.** It stops injection, certificate issuing and every change, for everyone.
