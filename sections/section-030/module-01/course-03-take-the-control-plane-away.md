# Take The Control Plane Away

Reading about a control plane outage is not the same as seeing one. In this part you scale `istiod` to zero on purpose and watch which half of the mesh notices. Pods that are already running carry on. Anything new, such as a fresh pod, cannot be created. Then you bring `istiod` back and see that nothing was lost, only delayed.

## The validation webhook, working

Start with the case that behaves well. When you apply an Istio object, the Kubernetes API server calls the validating admission webhook `validation.istio.io` and waits while `istiod` checks the object. If the object is clearly invalid, `istiod` refuses it at once. The `VirtualService` below has one HTTP rule for the `notification-service` Service that both redirects the request and routes it to a destination. A rule may do one or the other, never both.

<!-- astrona:playground:renew -->

Save this as `virtualservice-redirect-and-route.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: redirect-and-route
  namespace: cphealth-demo
spec:
  hosts:
    - notification-service
  http:
    - redirect:
        uri: /v2
      route:
        - destination:
            host: notification-service
```

Apply it:

```sh
kubectl apply -f virtualservice-redirect-and-route.yaml
```

You should see something like:

```text
Error from server: error when creating "virtualservice-redirect-and-route.yaml": admission webhook "validation.istio.io" denied the request: configuration is invalid: HTTP route cannot contain both route and redirect
```

The message names the component that refused the object: `admission webhook "validation.istio.io"`, which is `istiod`, called by the API server during your write. Everything needed to judge the object was inside the object, so `istiod` decided at once, and the object was never stored. Keep this exchange in mind, because next you remove one side of it.

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

Existing traffic is only half the picture. The other half is anything that must be **new**: a new pod, a changed route, a renewed certificate. Restarting a Deployment tests the first one at once. Restart the Deployment of the application, then look at the pods and at the `FailedCreate` events in the namespace:

```sh
kubectl -n cphealth-demo rollout restart deployment notification-service-v1
kubectl -n cphealth-demo get pods
kubectl -n cphealth-demo get events --field-selector reason=FailedCreate
```

You should see something like this for the first two commands:

```text
deployment.apps/notification-service-v1 restarted
NAME                                       READY   STATUS    RESTARTS   AGE
notification-service-v1-54dd46d4b6-flm8c   2/2     Running   0          13s
tester-69699fd775-96h4j                    2/2     Running   0          13s
```

The pod list has no new `notification-service-v1` pod. The old pod is still `Running` and still answering; that was the `200` you just saw. The new pod was **never created at all**. The last command lists a `Warning` event with the reason `FailedCreate` on the new ReplicaSet. Its message says that the API server failed calling the webhook `sidecar-injector.istio.io`, and the event explains why. The ReplicaSet controller asked the API server to create the pod. The API server tried to call the injection webhook `sidecar-injector.istio.io`, could not reach it, and the webhook's `failurePolicy: Fail` turned that into a refusal of the whole pod. A write of any Istio object fails in the same way now, because the validation webhook also has `failurePolicy: Fail` once `istiod` has started.

The `failurePolicy` is a real design choice with two defensible answers, and Istio's default for injection is the safer one:

| `failurePolicy` | During an `istiod` outage | Trade-off |
| --- | --- | --- |
| `Fail` (Istio default) | Pod creation is refused. Nothing new starts. | Loud. It blocks deployments, possibly including the one that would fix `istiod`. |
| `Ignore` | Pods start **without a sidecar proxy**, outside the mesh | Quiet. Deployments succeed and produce pods with no sidecar, so no mesh policy applies to them. |

`Ignore` is the more dangerous of the two, because it looks like success. A rollout completes, pods show `1/1 Running`, and every `AuthorizationPolicy` and `PeerAuthentication` in that namespace does nothing for those pods. Read the setting on your own cluster once, so it is not abstract. The webhook configuration that injects pods in this install is `istio-revision-tag-default`: it belongs to the revision tag `default`, a stable name that points at the installed `istiod`. The older `istio-sidecar-injector` configuration is still there, but every entry in it is switched off with a selector that never matches. Print the name and `failurePolicy` of each entry in the active one:

```sh
kubectl get mutatingwebhookconfiguration istio-revision-tag-default \
  -o jsonpath='{range .webhooks[*]}{.name}{"  "}{.failurePolicy}{"\n"}{end}'
```

Every entry prints `Fail`, the value Istio installs for the injection webhook. That is what refused the new pod a moment ago.

## Recovery needs nothing but the control plane back

Bring `istiod` back and watch the mesh catch up by itself. Scale it up, wait for it and for the application, then list the proxies with `istioctl proxy-status -v 1`, which shows every proxy connected to `istiod` and, for each type of configuration, whether the proxy confirmed the latest version:

```sh
kubectl -n istio-system scale deploy istiod --replicas=1
kubectl -n istio-system rollout status deploy istiod --timeout=120s
kubectl -n cphealth-demo rollout status deployment notification-service-v1 --timeout=120s
istioctl proxy-status -v 1
```

You should see something like this (the `Waiting for deployment` lines are left out):

```text
deployment.apps/istiod scaled
deployment "istiod" successfully rolled out
deployment "notification-service-v1" successfully rolled out
NAME                                                       CLUSTER        CDS             ECDS        EDS             LDS             RDS             ISTIOD                      VERSION
notification-service-v1-759d664778-fjz6v.cphealth-demo     Kubernetes     SYNCED (0s)     IGNORED     SYNCED (0s)     SYNCED (0s)     SYNCED (0s)     istiod-7dc9684c55-5nbpt     1.30.5
```

Only the new `notification-service-v1` pod is listed. The other proxies, the `tester` pod and the two gateways, were connected to the old `istiod` pod. They reconnect to the new one on their own within a few seconds, so run `istioctl proxy-status -v 1` again and they appear too. You did not apply anything again. The ReplicaSet controller kept retrying the pod creation. This time the webhook answered, the sidecar was injected, and the proxies reconnected on their own. `SYNCED` in every used column means each proxy confirmed the latest configuration `istiod` sent. `IGNORED` only means the proxy never asked for that type.

Nothing was lost, only delayed. That is the right expectation for any pure control plane outage. If something *does* need to be applied again afterwards, the outage was not the whole story.

> [!TIP]
> After any control plane incident, check `RESTARTS` and run `istioctl proxy-status -v 1`. If every proxy is listed and `SYNCED`, the mesh has caught up by itself.

You have now seen both halves of an outage. Running pods kept serving requests with stored configuration and certificates, while new pods were refused because the injection webhook could not be reached. Scaling `istiod` back up was the whole fix. One case is still open: an object that the cluster stored even though it was invalid, and that `istiod` then serves as it is.

## Common pitfalls

> [!WARNING]
> - **Reading working traffic as a healthy control plane.** During the outage the request still returned `200`. Only something new, such as a pod restart, shows the problem.
> - **Setting the injection webhook to `Ignore` to unblock deployments.** It turns a loud failure into pods quietly outside the mesh, which is the more expensive problem.
> - **Restarting workloads while `istiod` is down.** The new pods cannot be created, and the old ones keep running.
> - **Applying everything again after recovery.** A pure outage loses nothing. If applying again seems needed, look for a second cause.
> - **Scaling `istiod` on a shared cluster to test a theory.** It stops injection, certificate issuing and every change, for everyone.
