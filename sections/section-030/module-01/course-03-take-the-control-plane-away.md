# Take Mission Control Away

Astronaut, in this part you switch off mission control (`istiod`) on purpose and watch which half of the mesh notices. Ships already in flight carry on. Anything new, such as a fresh pod, gets stuck at the launch pad. Then you bring mission control back and see that nothing was lost, only delayed.

## The validation webhook, working

Start with the case that behaves well. The validation webhook is the registry clerk: when you apply an Istio object, the Kubernetes API server (the registry office) calls `istiod` and waits while `istiod` checks the form. If the form is clearly invalid, `istiod` refuses it on the spot.

<!-- astrona:playground:renew -->

### Watch the clerk refuse an invalid form

This `VirtualService` (a flight plan for the `notification-service` beacon) sends 60% of signals one way and 60% another way. The weights add up to 120, which is impossible.

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

You should see something like this (it was recorded with the YAML sent on standard input, so it says `STDIN` where you will see your file name):

```text
Error from server: error when creating "STDIN": admission webhook "validation.istio.io" denied the request:
configuration is invalid: total destination weight 120 != 100
```

Look at who refused it: `admission webhook "validation.istio.io"`. That is `istiod`, called by the API server during your write. Everything needed to judge the form was inside the form itself, so the clerk could decide straight away. The object was never stored.

Keep this conversation in mind. Next, you remove one of the two people in it.

## Taking the control plane away

Now scale `istiod` down to zero pods. Mission control goes silent.

> [!WARNING]
> This step stops `istiod`. In this throwaway playground it is harmless and you undo it at the end. On a shared cluster it stops sidecar injection, certificate issuing and every configuration change for everyone, and it starts the clock that breaks mutual TLS when the certificates expire. Never run it there out of curiosity.

### Send a signal while mission control is down

Stop `istiod`, wait for it to be gone, and send a signal from your test ship:

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

Mission control is gone, and the signal still got through. Each proxy routes with the orders it already holds, and the mutual TLS handshake uses badges (certificates) that were already issued. This is exactly why control plane outages are easy to miss and expensive to leave running.

## What stops, and why it stops that way

Existing traffic is only half the picture. The other half is anything that needs to be **new**: a new pod, a changed route, a renewed certificate. Restarting a Deployment tests the first one right away.

### Try to launch a new ship

Restart the app's Deployment, then look at the pods and at the events on its ReplicaSet:

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

The old pod is still `Running` and still answering; that was the `200` you just saw. The new pod was **never created at all**. The event text explains why. The API server tried to call the injection webhook (the launch-pad crew that puts a communications officer on board), could not reach it, and the webhook's `failurePolicy: Fail` turned that into a refusal of the whole pod.

### Fail or Ignore

The `failurePolicy` is a real design choice with two defensible answers, and Istio's default is the safer one:

| `failurePolicy` | During an `istiod` outage | Trade-off |
| --- | --- | --- |
| `Fail` (Istio default) | Pod creation is refused. Nothing new starts. | Loud. Blocks deployments, possibly including the deployment that would fix `istiod`. |
| `Ignore` | Pods start **without a sidecar**, outside the mesh | Quiet. Deployments succeed and produce ships with no communications officer, exempt from every mesh policy. |

`Ignore` is the more dangerous of the two, because it looks like success. A rollout completes, pods show `1/1 Running`, and every `AuthorizationPolicy` and `PeerAuthentication` in that namespace now does nothing for those pods.

Look at the setting on your own cluster once, so it is not abstract:

```sh
kubectl get mutatingwebhookconfiguration istio-sidecar-injector \
  -o jsonpath='{.webhooks[0].failurePolicy}{"\n"}'
```

## Recovery needs nothing but the control plane back

Bring mission control back and watch the mesh catch up by itself.

### Bring istiod back

Scale `istiod` up again, wait for it and for the app, then take the roll call:

```sh
kubectl -n istio-system scale deploy istiod --replicas=1
kubectl -n istio-system rollout status deploy istiod --timeout=120s
kubectl -n cphealth-demo rollout status deployment notification-service-v1 --timeout=120s
istioctl proxy-status
```

You should see something like:

```text
deployment "istiod" successfully rolled out
deployment "notification-service-v1" successfully rolled out
NAME                                       CLUSTER     CDS       LDS       EDS       RDS
notification-service-v1-...cphealth-demo   Kubernetes  SYNCED    SYNCED    SYNCED    SYNCED
tester-...cphealth-demo                    Kubernetes  SYNCED    SYNCED    SYNCED    SYNCED
```

You did not re-apply anything. The ReplicaSet kept retrying the pod creation; this time the webhook answered, injection worked, and the proxies reconnected on their own. `istioctl proxy-status` is mission control's roll call: every ship answers, and `SYNCED` means it holds the latest orders.

Nothing was lost, only delayed. That is the right expectation for any pure control plane outage. If something *does* need re-applying afterwards, the outage was not the whole story.

> [!TIP]
> After any control plane incident, check `RESTARTS` and run `istioctl proxy-status`. If every row is back and `SYNCED`, the mesh has caught up by itself.

## Common pitfalls

> [!WARNING]
> - **Reading working traffic as a healthy control plane.** During the outage the signal still returned `200`. Only something new, such as a pod restart, shows the problem.
> - **Setting the injection webhook to `Ignore` to unblock deployments.** It turns a loud failure into quietly unmeshed workloads, which is the more expensive problem.
> - **Restarting workloads while `istiod` is down.** The new pods cannot be created, and the old ones keep running.
> - **Re-applying everything after recovery.** A pure outage loses nothing. If re-applying seems needed, look for a second cause.
> - **Scaling `istiod` on a shared cluster to test a theory.** It stops injection, certificate issuing and every change, for everyone.

> *Existing traffic surviving an outage is not good news; it is the symptom that hides the outage.*
