# Solution: The Mesh Works And Nothing Can Change

## Step 1 — Trust the symptom, not the dashboards

Traffic flowing proves nothing about the control plane. Each proxy serves from
configuration it already holds and a certificate it already has. The useful test
is whether anything can **change**:

```sh
kubectl -n istio-system get pods -l app=istiod
kubectl -n istio-system get deploy istiod
```

```text
No resources found in istio-system namespace.
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
istiod   0/0     0            0           31m
```

`istiod` is scaled to zero. That single fact explains all three reports: the
applied `VirtualService` was never pushed, the colleague's pods cannot be
created because the injection webhook is unreachable, and existing traffic is
unaffected because proxies are running on cached configuration.

## Step 2 — Restore the control plane

```sh
kubectl -n istio-system scale deploy istiod --replicas=1
kubectl -n istio-system rollout status deploy istiod --timeout=180s
```

```sh
astrona submit
```

Nothing needs re-applying afterwards — a control plane outage delays changes, it
does not lose them.

## Step 3 — Find the object that will never be served

With `istiod` back, look at what it makes of the namespace. `kubectl get` shows
the object and `kubectl describe` shows no events, because Istio networking
resources carry no status conditions to turn red. Two places hold the truth:

```sh
kubectl -n istio-system logs deploy/istiod --tail=200 | grep -i -E 'reject|invalid'
kubectl -n istio-system exec deploy/istiod -- \
  curl -s localhost:15014/metrics | grep -E 'pilot_total_xds_rejects|pilot_xds_push_errors'
istioctl analyze -n cphealth-demo
```

```text
Error [IST0101] ... total destination weight 120 != 100
```

The `bad-weights` `VirtualService` has two destinations at `weight: 60`. It
reached etcd because the validating webhook was unavailable when it was applied;
`istiod` refuses it every time it tries to build configuration from it.

Note `pilot_total_xds_rejects` may be **absent** rather than zero — a Prometheus
counter that has never incremented is usually not emitted at all, and absence
there is good news.

## Step 4 — Remove or correct it

Either is acceptable. Removing it is the honest choice if nobody wanted a
weighted split:

```sh
kubectl -n cphealth-demo delete virtualservice bad-weights
```

Correcting it, if the split was intended:

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > virtualservice-bad-weights.yaml <<'EOF'
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
EOF
kubectl apply -f virtualservice-bad-weights.yaml
```

With `istiod` healthy the webhook now enforces again, so an attempt to re-apply
the original would be refused at `kubectl apply` time — which is the system
working as designed.

```sh
astrona submit
```

## Step 5 — Verify convergence, not just traffic

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

`SYNCED` proves the proxies acknowledged what `istiod` sent. The `200` proves
the result works. Neither alone is sufficient.

```sh
astrona submit
```

## Why the shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| Re-apply the object because "nothing happened" | re-applying identical content does not retry a push; the rejection repeats |
| Reinstall Istio | destroys the evidence and the mesh's existing state for an outage that needed one `scale` |
| Restart the workload pods | with `istiod` down they never become ready; with it up they were never the problem |
| Leave the webhook `failurePolicy` at `Ignore` | invalid configuration keeps being accepted silently |

## Common mistakes

- Concluding the mesh is fine because traffic still flows during an `istiod`
  outage. Proxies are running on cached config.
- Looking for a rejected configuration in `kubectl apply` output. It succeeded;
  the rejection happened later, inside `istiod`.
- Ignoring `istiod` restarts. An `OOMKilled` control plane produces intermittent,
  hard-to-reproduce symptoms.
- Restarting workloads while `istiod` is down — they will not get config and
  will stay unready.

## Practice variations

- Lower the `istiod` memory limit until it is `OOMKilled` and observe the
  mesh-wide symptoms.
- Delete the validating webhook configuration and watch invalid config become
  acceptable again.
- Run `istioctl bug-report` and look at what it collects from the control plane.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Common problems: network issues](https://istio.io/latest/docs/ops/common-problems/) — the catalogue of 503 causes and how to tell them apart
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
