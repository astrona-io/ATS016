# Part 3 — Outage Anatomy And Rejected Configuration

> Prerequisite: [Part 2 — The Instruments](./course-02-instruments-logs-and-metrics.md). Next: [the module landing page](./course.md), then [module 030-02](../module-02/course.md).

Parts 1 and 2 described the failures and the instruments. This part produces one, deliberately, and watches which half of the mesh notices — then covers the failure that produces no outage at all and is consequently the hardest to find: configuration the API server stored and `istiod` refused to push.

## The validation webhook, working

Start with the case that behaves well, because the misbehaving case is defined by its absence. Job 4 from [Part 1](./course-01-the-four-jobs-of-istiod.md) rejects invalid Istio resources at apply time, synchronously, while you watch.

> [!TIP]
> **Try it — the validation webhook doing its job**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: bad-weights
>   namespace: cphealth-demo
> spec:
>   hosts:
>     - notification-service
>   http:
>     - route:
>         - destination:
>             host: notification-service
>           weight: 60
>         - destination:
>             host: notification-service
>           weight: 60
> EOF
> ```
>
> Expect something like:
>
> ```text
> Error from server: error when creating "STDIN": admission webhook "validation.istio.io" denied the request:
> configuration is invalid: total destination weight 120 != 100
> ```
>
> The rejection is spoken by `admission webhook "validation.istio.io"` — that is `istiod`, reached synchronously by the API server during your write. Everything needed for the verdict was inside the document, which is why the webhook could reach it ([module 010-01 Part 1](../../section-010/module-01/course-01-admission-and-the-analysis-gap.md) has the general rule).

Now hold that interaction in mind and remove one participant from it.

## Taking the control plane away

> [!WARNING]
> The next checkpoint scales `istiod` to zero. In this throwaway playground that is harmless and reversible. On any shared cluster it stops sidecar injection, certificate issuance and every configuration change for everyone using the mesh — and, per [Part 1](./course-01-the-four-jobs-of-istiod.md), begins a clock that breaks mTLS entirely within a certificate lifetime. Never run it there to satisfy curiosity.

> [!TIP]
> **Try it — traffic during a control plane outage**
>
> ```sh
> kubectl -n istio-system scale deploy istiod --replicas=0
> kubectl -n istio-system rollout status deploy istiod --timeout=60s
> kubectl -n cphealth-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'existing traffic: %{http_code}\n' -X POST http://notification-service/notify
> ```
>
> Expect something like:
>
> ```text
> deployment.apps/istiod scaled
> deployment "istiod" successfully rolled out
> existing traffic: 200
> ```
>
> The control plane is gone and the request succeeded. Both caches from Part 1 are doing their work: the proxies are routing from configuration they already hold, and the mTLS handshake used certificates already issued. This is the fact that makes control plane outages easy to miss and expensive to leave running.

## What stops, and why it stops that way

Existing traffic is half the picture. The other half is anything that needs to be **new** — a new pod, a changed route, a renewed certificate. Forcing a Deployment restart exercises the first immediately.

> [!TIP]
> **Try it — what stops during the same outage**
>
> ```sh
> kubectl -n cphealth-demo rollout restart deployment notification-service-v1
> kubectl -n cphealth-demo get pods
> kubectl -n cphealth-demo describe replicaset -l app=notification-service | tail -15
> ```
>
> Expect something like:
>
> ```text
> NAME                                      READY   STATUS    RESTARTS   AGE
> notification-service-v1-6c9f8b7d5-x2kqp   2/2     Running   0          14m
>
>   Warning  FailedCreate  ... Error creating: Internal error occurred: failed calling webhook
>   "sidecar-injector.istio.io": failed to call webhook: ... connection refused
> ```
>
> The old pod is still `Running` and still serving — that is the `200` from the previous checkpoint. The replacement was **never created at all**. Read the mechanism in the event text: the API server tried to call the mutating webhook, could not reach it, and the webhook's `failurePolicy: Fail` turned that into a refusal of the whole pod creation.

That `failurePolicy` is a genuine design choice with two defensible answers, and Istio's default is the safer one:

| `failurePolicy` | During an `istiod` outage | Trade-off |
| --- | --- | --- |
| `Fail` (Istio default) | Pod creation is rejected. Nothing new starts. | Loud. Blocks deployments — including, potentially, the deployment that would fix `istiod`. |
| `Ignore` | Pods start **without a sidecar**, outside the mesh | Quiet. Deployments succeed and produce workloads exempt from every mesh policy. |

`Ignore` is the more dangerous of the two precisely because it looks like success. A rollout completes, pods are `1/1 Running`, and every `AuthorizationPolicy` and `PeerAuthentication` in that namespace now applies to nothing on those pods. The evidence is subtle enough that [module 030-03](../module-03/course.md) exists to find it.

The object itself is worth looking at once so the setting is not abstract:

```sh
kubectl get mutatingwebhookconfiguration istio-sidecar-injector \
  -o jsonpath='{.webhooks[0].failurePolicy}{"\n"}'
```

## Recovery needs nothing but the control plane back

> [!TIP]
> **Try it — recovery**
>
> ```sh
> kubectl -n istio-system scale deploy istiod --replicas=1
> kubectl -n istio-system rollout status deploy istiod --timeout=120s
> kubectl -n cphealth-demo rollout status deployment notification-service-v1 --timeout=120s
> istioctl proxy-status
> ```
>
> Expect something like:
>
> ```text
> deployment "istiod" successfully rolled out
> deployment "notification-service-v1" successfully rolled out
> NAME                                       CLUSTER     CDS       LDS       EDS       RDS
> notification-service-v1-...cphealth-demo   Kubernetes  SYNCED    SYNCED    SYNCED    SYNCED
> tester-...cphealth-demo                    Kubernetes  SYNCED    SYNCED    SYNCED    SYNCED
> ```
>
> Nothing had to be re-applied. The ReplicaSet was still retrying pod creation, the webhook answered this time, injection succeeded, and the proxies reconnected on their own. Nothing was lost — only delayed. That is the correct expectation for any pure control plane outage, and a useful sanity check: if something *does* need re-applying afterwards, the outage was not the whole story.

## Accepted, never applied

Now the failure with no outage. Consider what the first checkpoint's `apply` does when `istiod` is unavailable **and** the validating webhook's `failurePolicy` permits the write to proceed. The object is stored. `kubectl apply` prints `created`. Nothing anywhere reports a problem. And when `istiod` returns, it reads the object, finds it invalid, and never pushes it.

The same end state arrives by a second route with the control plane fully healthy: a configuration that is valid to the webhook but that a **proxy** refuses when it arrives — a NACK, which is what `pilot_total_xds_rejects` counts.

Either way, every ordinary tool lies to you:

| You run | It says | Reality |
| --- | --- | --- |
| `kubectl get` | the object exists | it does |
| `kubectl describe` | no events, no conditions | Istio networking resources have no status to turn red |
| a request | behaves as though the object were absent | for the proxies, it is |
| `istioctl proxy-status` | possibly `STALE` for the affected type | the one hint, and easy to miss |

Two places carry the truth, and checking both is the last step of any "I applied it and nothing happened" investigation:

```sh
kubectl -n istio-system logs deploy/istiod --tail=200 | grep -i -E 'reject|invalid'
kubectl -n istio-system exec deploy/istiod -- \
  curl -s localhost:15014/metrics | grep -E 'pilot_total_xds_rejects|pilot_xds_push_errors'
```

Remember from [Part 2](./course-02-instruments-logs-and-metrics.md) that those metrics are **absent** when they have never incremented. A line appearing at all is the signal; its value is secondary.

## The investigation order

Putting the module together, the sequence for a suspected control plane problem:

```text
  1. kubectl get pods -l app=istiod        ready? restarts? age?
  2. logs | grep -iE 'reject|error|warn'   what is it complaining about?
  3. metrics: pushes / rejects / errors    is anything converging?
  4. make a trivial change, re-read (1-3)  does a change actually propagate?
  5. istioctl proxy-status                 did it land on the proxies?
```

Step 4 is the one that distinguishes a frozen mesh from a healthy one, because every earlier step can look fine on a control plane that is not doing its job.

> [!WARNING]
> **Pitfalls around outages and rejects**
>
> - **Trusting `kubectl apply` output when the validation webhook may have been bypassed.** If `istiod` was unavailable when a change was applied, the object can exist and never have been pushed.
> - **Expecting `kubectl describe` to show a rejection.** Istio networking resources carry no status conditions. The `istiod` log and `pilot_total_xds_rejects` are the only witnesses.
> - **Setting the injection webhook to `Ignore` to unblock deployments.** It converts a loud failure into silently unmeshed workloads, which is the more expensive problem.
> - **Re-applying an object because nothing happened.** Re-applying identical content changes nothing; it does not retry a push. Fix the rejection or the delivery.
> - **Scaling `istiod` on a shared cluster to test a theory.** It stops injection, certificate issuance and every change, for everyone.

> *Existing traffic surviving an outage is not reassurance — it is the symptom that makes the outage hard to notice.*

## Reference

- [Dynamic admission control — failure policy](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/#failure-policy) — the exact semantics of `Fail` and `Ignore`.
- [Istio sidecar injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) — the injector webhook object, its selectors and its failure policy.
- [Common problems — traffic management](https://istio.io/latest/docs/ops/common-problems/network-issues/) — symptom-first, including "my configuration had no effect".
- `kubectl -n istio-system logs deploy/istiod --previous` — the log from before the last restart; where the evidence lives after a crash loop.
