# Part 1 — How Injection Actually Happens

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — Labels, Selectors And Precedence](./course-02-labels-and-precedence.md).

Almost every wrong belief about sidecar injection comes from imagining it as something Istio does to your Deployment, continuously, like a controller. It is not. It is a single synchronous edit made to a Pod object while the API server is holding the request open, and everything surprising about injection follows from that one fact.

## The path a pod takes

```text
   kubectl apply / a ReplicaSet creates a Pod
            │
            ▼
   API server: authentication, authorization
            │
            ▼
   MUTATING ADMISSION
     ├─ does the namespaceSelector match this pod's namespace?   ─── no ──▶ skip
     ├─ does the objectSelector match this pod?                  ─── no ──▶ skip
     └─ yes: POST the Pod to istiod at :15017
                     │
                     ▼
             istiod returns a JSONPatch:
               + initContainer istio-init   (or the Istio CNI plugin instead)
               + container     istio-proxy
               + volumes       istio-envoy, istio-token, istio-ca-root-cert, ...
               + labels/annotations
                     │
                     ▼
     API server applies the patch to the Pod object
            │
            ▼
   SCHEMA VALIDATION → VALIDATING ADMISSION → etcd
            │
            ▼
   the scheduler sees a Pod that has ALWAYS had two containers
```

The scheduler, the kubelet and every subsequent reader see a pod that was born with a sidecar. There is no record of the edit in the pod itself beyond the injected content and an annotation naming the injection template used.

## What gets added, and why each piece

| Added | Purpose |
| --- | --- |
| `istio-proxy` container | Envoy plus `pilot-agent` — the proxy itself |
| `istio-init` init container | runs `iptables` rules that redirect the pod's traffic into Envoy |
| `istio-token` volume | a projected ServiceAccount token, used to authenticate to `istiod` |
| `istio-ca-root-cert` volume | the mesh root certificate, to validate `istiod` |
| `istio-envoy` volume | an in-memory volume for the proxy's runtime material |

The init container is the part that makes interception transparent. It installs `iptables` rules in the pod's network namespace that redirect outbound traffic to port 15001 and inbound traffic to 15006 — the two listeners [section 040](../../section-040/module-01/course.md) examines. Your application connects to `notification-service:80` exactly as it always did and never learns that something intervened.

That also explains a class of exclusions: a pod that shares the **node's** network namespace (`hostNetwork: true`) cannot have those rules applied safely, because they would affect the node rather than the pod. [Part 3](./course-03-working-the-checklist.md) returns to that.

Two implementation notes worth having, because they change what you will see on a real cluster. First, some installs use the **Istio CNI plugin** instead of the init container: the same `iptables` work is done by a CNI plugin at pod network setup time, so `istio-init` is absent and the pod needs no elevated capabilities. Second, newer Kubernetes versions allow the proxy to be a **native sidecar** — an init container with `restartPolicy: Always` — which fixes long-standing startup-ordering problems. Either way, the decision path above is unchanged.

The content of the patch comes from a template stored in the `istio-sidecar-injector` ConfigMap in `istio-system`. It is worth knowing that exists: when injection produces something unexpected — a wrong image, a missing environment variable, resource limits you did not set — the template is where the answer is, and it is also where a per-revision customisation would have been made.

## Three consequences

**1. It happens at pod creation only.** There is no reconciliation loop. Nothing will ever add a sidecar to a pod that already exists, no matter how many labels you fix. The only way to inject an existing workload is to replace its pods.

**2. It modifies the Pod, not the Deployment.** `kubectl get deployment -o yaml` will never show `istio-proxy`. This is not a display quirk — the Deployment genuinely does not contain it. Check the pod, or the ReplicaSet's created pods; never the controller.

**3. It depends on `istiod` being reachable at that moment.** Injection is a synchronous call on the critical path of a pod creation. That is why the injection webhook appeared as one of the four jobs in [module 030-01](../module-01/course-01-the-four-jobs-of-istiod.md), and why its `failurePolicy` decides whether an `istiod` outage blocks deployments or silently produces unmeshed pods.

## Is it in the mesh?

Two checks answer this. They cost the same and fail differently, so it is worth knowing both.

> [!TIP]
> **Try it — which pods have a proxy**
>
> ```sh
> kubectl -n noinject-demo get pods \
>   -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[*].ready,CONTAINERS:.spec.containers[*].name'
> ```
>
> Expect something like:
>
> ```text
> POD                                       READY        CONTAINERS
> notification-service-v1-6c9f8b7d5-x2kqp   true,true    notification-service,istio-proxy
> reporting-service-7fd4c8b96-mn5tp         true         reporting-service
> tester-6d9f7b8c5-hj4kz                    true,true    tester,istio-proxy
> ```
>
> `reporting-service` has one container where the others have two. It is healthy, ready and serving — and outside the mesh. Nothing in this output is an error, which is exactly why this state survives code review and reaches production. The shorthand in day-to-day use is the `READY` column of plain `kubectl get pods`: `2/2` versus `1/1`.

The second check comes from a different direction entirely — `istioctl analyze` reads pods against the mesh's expectations and reports the gap.

> [!TIP]
> **Try it — the analyzer's version of the same finding**
>
> ```sh
> istioctl analyze -n noinject-demo
> ```
>
> Expect something like:
>
> ```text
> Info [IST0103] (Pod reporting-service-7fd4c8b96-mn5tp.noinject-demo) The pod is missing the Istio proxy. This can often be resolved by restarting or redeploying the workload.
> ```
>
> Note the severity — `Info`, the lowest there is. A workload silently excluded from every mesh policy you have written is reported at the same level as a style note. This is [module 010-01 Part 2's](../../section-010/module-01/course-02-reading-analyzer-messages.md) severity lesson in its most expensive form, and a good argument for reading analyzer output to the bottom.
>
> The message's suggested resolution — "restarting or redeploying" — is consequence 1 above, stated as advice. It is correct *once the cause is fixed*, and useless before that.

## Why this matters more than it looks

A workload outside the mesh is not degraded, it is exempt:

- `PeerAuthentication` in `STRICT` mode does not apply to it — it sends and receives plaintext.
- `AuthorizationPolicy` does not apply to it — nothing inspects its requests.
- No telemetry is produced for it, so it is absent from Kiali's graph and from every Grafana dashboard ([section 060](../../section-060/module-01/course.md)).
- It does not appear in `istioctl proxy-status` ([module 030-02](../module-02/course.md)).

The compounding problem is that each of those absences looks like a different bug. A security review sees a policy that "works"; a dashboard shows a service that "has no traffic"; a sync check shows a proxy that "is not there". One cause, four symptoms, none of which names it.

> [!WARNING]
> **Pitfalls in the mechanism**
>
> - **Labelling a namespace and expecting existing pods to change.** Injection happens at pod creation. Without recreation the label is aspirational.
> - **Looking for `istio-proxy` in the Deployment.** It is added to the Pod. The Deployment never contains it.
> - **Assuming a `Running` pod is a meshed pod.** Kubernetes has no opinion about the mesh. Count containers.
> - **Trusting `IST0103` to be prominent.** It is `Info` severity, at the bottom of the output.
> - **Expecting `hostNetwork: true` pods to be injected.** Traffic redirection cannot be applied to the node's network namespace, so they never are.

> *Injection is one synchronous edit to a Pod at admission time — which is why nothing can ever retrofit it.*

## Reference

- [Installing the sidecar](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) — automatic and manual injection, and the `istioctl kube-inject` command for the offline case.
- [Dynamic admission control](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) — mutating webhooks, JSONPatch responses, and `failurePolicy`.
- [Istio CNI plugin](https://istio.io/latest/docs/setup/additional-setup/cni/) — the alternative to `istio-init`, and what changes in the pod when it is in use.
- `kubectl -n istio-system get configmap istio-sidecar-injector -o yaml` — the injection template on your own cluster; the source of everything the patch adds.
