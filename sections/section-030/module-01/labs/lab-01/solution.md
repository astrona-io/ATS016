# Solution: The Mesh Works And Nothing Can Change

Three reports point at one component: `istiod`, Istio's control plane. This walkthrough checks the control plane, brings it back, finds the invalid object that was stored without validation, and proves the mesh has caught up.

## Step 1: Trust the symptom, not the dashboards

Working traffic proves nothing about the control plane. Each sidecar proxy serves with the configuration it already holds and a certificate it already has. The useful question is whether anything can **change**. Look at `istiod`:

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

- Changes to the namespace are not sent to the proxies.
- The colleague's new pods cannot be created, because the API server cannot reach the injection webhook.
- Existing traffic is fine, because the proxies run on their stored configuration.

## Step 2: Restore the control plane

Scale `istiod` back to one replica and wait for it:

```sh
kubectl -n istio-system scale deploy istiod --replicas=1
kubectl -n istio-system rollout status deploy istiod --timeout=180s
```

Nothing needs to be applied again afterwards. A control plane outage delays changes; it does not lose them. That includes the invalid object: once `istiod` is back, it sends it to the proxies as it is. The proxies reconnect on their own retry timer, which can take up to a minute, so wait for that before you send the request again:

```sh
sleep 60
kubectl -n cphealth-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' -X POST http://notification-service/notify
```

```text
301 http://notification-service/v2
```

The request that returned `200` before now gets a redirect to `/v2`, which nobody configured on purpose.

Submit now to see your progress. The `istiod` check should pass, and the check for the invalid object still fails:

```sh
astrona submit
```

## Step 3: Find the object that was stored without validation

With `istiod` back, ask what it makes of the namespace. `kubectl get` lists the object and `kubectl describe` shows no events, because Istio networking objects have no status field that reports a problem. `istiod` does not check a stored object again, so its log and metrics say nothing about it either. `istioctl analyze` is the tool that names it. The log and counter checks below are still worth running, because they would show the other case, a proxy that refused configuration:

```sh
kubectl -n istio-system logs deploy/istiod --tail=200 | grep -i -E 'reject|invalid'
kubectl -n istio-system exec deploy/istiod -- \
  curl -s localhost:15014/metrics | grep -E 'pilot_total_xds_rejects|pilot_total_xds_internal_errors'
istioctl analyze -n cphealth-demo
```

The analyzer reports an `Error` with the code `IST0106` (`SchemaValidationError`) on `VirtualService cphealth-demo/bad-redirect`, with the reason `HTTP route cannot contain both route and redirect`. Its one HTTP rule both redirects the request and routes it, which a rule may never do. It was stored in etcd only because both validating webhooks were skipped when it was applied; with the webhooks working, `kubectl apply` refuses it. `istiod` serves the rule as it is, and the redirect is what the proxies apply.

`pilot_total_xds_rejects` may be **missing** rather than zero. A counter that has never gone up is usually not shown at all, and a missing line there is good news.

## Step 4: Remove or correct it

Either fix is accepted. Removing the object is the right choice if nobody needs it:

```sh
kubectl -n cphealth-demo delete virtualservice bad-redirect
```

If the route was intended, correct it instead, so the rule only routes.

Save this as `virtualservice-bad-redirect.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bad-redirect
  namespace: cphealth-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
```

Apply it:

```sh
kubectl apply -f virtualservice-bad-redirect.yaml
```

With `istiod` healthy, the validation webhook checks Istio objects again. If you tried to apply the original object now, `kubectl apply` would refuse it at once. That is the system working as designed.

Submit again:

```sh
astrona submit
```

## Step 5: Prove the proxies caught up, not just traffic

List the proxies with their sync state, run the analyzer, and send a real request from the `tester` pod. The proxies reconnect to `istiod` on their own retry timer, which can take up to a minute after `istiod` is back. If the `proxy-status` table shows only its header line, wait 30 seconds and run it again:

```sh
istioctl proxy-status -v 1 | grep -E '^NAME|cphealth-demo'
istioctl analyze -n cphealth-demo
kubectl -n cphealth-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
```

```text
NAME                                                       CLUSTER        CDS             ECDS        EDS              LDS             RDS             ISTIOD                      VERSION
notification-service-v1-54dd46d4b6-5gx5h.cphealth-demo     Kubernetes     SYNCED (0s)     IGNORED     SYNCED (47s)     SYNCED (0s)     SYNCED (0s)     istiod-7dc9684c55-bzfh6     1.30.5
tester-69699fd775-2gdqt.cphealth-demo                      Kubernetes     SYNCED (0s)     IGNORED     SYNCED (62s)     SYNCED (0s)     SYNCED (0s)     istiod-7dc9684c55-bzfh6     1.30.5
✔ No validation issues found when analyzing namespace: cphealth-demo.
200
```

Since Istio 1.27, plain `istioctl proxy-status` shows no per-type sync state, so use `-v 1`. `IGNORED` only means the proxy never asked for that type.

`SYNCED` proves the proxies confirmed what `istiod` sent. The `200` proves the result works. You need both.

Submit for the final grade:

```sh
astrona submit
```

## Why the shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Apply the object again because "nothing happened" | The same content does not retry a push; the rejection repeats |
| Reinstall Istio | Destroys the evidence and the mesh's state, for an outage that needed one `scale` |
| Restart the workload pods | With `istiod` down they cannot be created; with it up they were never the problem |
| Set the validation webhook `failurePolicy` to `Ignore` | Invalid configuration keeps being stored without a check |

## Common mistakes

- Deciding the mesh is fine because traffic still flows during an `istiod` outage. The proxies are running on stored configuration.
- Looking for the rejection in the `kubectl apply` output. The apply succeeded; the rejection happened later, inside `istiod`.
- Ignoring `istiod` restarts. A control plane killed for lack of memory causes problems that come and go.
- Restarting workloads while `istiod` is down. Their new pods cannot be created.

## Practice variations

- Lower the `istiod` memory limit until it is `OOMKilled`, and watch the symptoms across the mesh.
- Set the validation webhook's `failurePolicy` to `Ignore`, scale `istiod` to zero, and apply an invalid object to see it stored.
- Run `istioctl bug-report` and look at what it collects from the control plane.
