# Solution: The Mesh Works And Nothing Can Change

Astronaut, three reports point at one place: mission control (`istiod`). This walkthrough checks the control plane, brings it back, finds the stored object it refuses, and proves the mesh has caught up.

## Step 1: Trust the symptom, not the dashboards

Working traffic proves nothing about the control plane. Each proxy serves from orders it already holds and a badge (certificate) it already has. The useful question is whether anything can **change**. Look at `istiod`:

```sh
kubectl -n istio-system get pods -l app=istiod
kubectl -n istio-system get deploy istiod
```

```text
No resources found in istio-system namespace.
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
istiod   0/0     0            0           31m
```

`istiod` is scaled to zero. That one fact explains all three reports:

- The applied `VirtualService` was never sent to the proxies.
- The colleague's new pods cannot be created, because the injection webhook cannot be reached.
- Existing traffic is fine, because the proxies run on their stored orders.

## Step 2: Restore the control plane

Scale `istiod` back to one replica and wait for it:

```sh
kubectl -n istio-system scale deploy istiod --replicas=1
kubectl -n istio-system rollout status deploy istiod --timeout=180s
```

Nothing needs re-applying afterwards. A control plane outage delays changes; it does not lose them.

Submit now to see your progress. The `istiod` check should pass, and the check for the invalid route weights still fails:

```sh
astrona submit
```

## Step 3: Find the object that will never be served

With `istiod` back, ask what it makes of the namespace. `kubectl get` lists the object and `kubectl describe` shows no events, because Istio networking objects have no status field to turn red. The truth lives in the `istiod` log and metrics, and the pre-flight inspector `istioctl analyze` names the object:

```sh
kubectl -n istio-system logs deploy/istiod --tail=200 | grep -i -E 'reject|invalid'
kubectl -n istio-system exec deploy/istiod -- \
  curl -s localhost:15014/metrics | grep -E 'pilot_total_xds_rejects|pilot_xds_push_errors'
istioctl analyze -n cphealth-demo
```

```text
Error [IST0101] ... total destination weight 120 != 100
```

The `bad-weights` `VirtualService` has two destinations, each at `weight: 60`. It reached the archive (etcd) because the validating webhook was not reachable when it was applied. `istiod` refuses it every time it builds configuration from it.

`pilot_total_xds_rejects` may be **missing** rather than zero. A counter that has never gone up is usually not shown at all, and a missing line there is good news.

## Step 4: Remove or correct it

Either fix is accepted. Removing it is the honest choice if nobody wanted a weighted split:

```sh
kubectl -n cphealth-demo delete virtualservice bad-weights
```

If the split was intended, correct it instead, so the weights add up to 100.

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
          weight: 100
```

Apply it:

```sh
kubectl apply -f virtualservice-bad-weights.yaml
```

With `istiod` healthy, the registry clerk (validation webhook) checks forms again. If you tried to apply the original object now, `kubectl apply` would refuse it on the spot. That is the system working as designed.

Submit again:

```sh
astrona submit
```

## Step 5: Prove convergence, not just traffic

Take the roll call, run the inspector, and send a real signal:

```sh
istioctl proxy-status
istioctl analyze -n cphealth-demo
kubectl -n cphealth-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

```text
NAME                                       CDS      LDS      EDS      RDS
notification-service-v1-...cphealth-demo   SYNCED   SYNCED   SYNCED   SYNCED
tester-...cphealth-demo                    SYNCED   SYNCED   SYNCED   SYNCED
✔ No validation issues found when analyzing namespace: cphealth-demo.
200
```

`SYNCED` proves the proxies confirmed what `istiod` sent. The `200` proves the result works. You need both.

Submit for the final grade:

```sh
astrona submit
```

## Why the shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Re-apply the object because "nothing happened" | Re-applying the same content does not retry a push; the rejection repeats |
| Reinstall Istio | Destroys the evidence and the mesh's state, for an outage that needed one `scale` |
| Restart the workload pods | With `istiod` down they cannot be created; with it up they were never the problem |
| Leave the webhook `failurePolicy` at `Ignore` | Invalid configuration keeps being accepted quietly |

## Common mistakes

- Deciding the mesh is fine because traffic still flows during an `istiod` outage. The proxies are running on stored orders.
- Looking for the rejection in the `kubectl apply` output. The apply succeeded; the rejection happened later, inside `istiod`.
- Ignoring `istiod` restarts. A control plane killed for lack of memory causes problems that come and go.
- Restarting workloads while `istiod` is down. Their new pods cannot be created.

## Practice variations

- Lower the `istiod` memory limit until it is `OOMKilled`, and watch the symptoms across the mesh.
- Delete the validating webhook configuration and watch invalid configuration become accepted again.
- Run `istioctl bug-report` and look at what it collects from the control plane.
