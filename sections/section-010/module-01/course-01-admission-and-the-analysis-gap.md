# Part 1 — What The API Server Checks, And What It Cannot

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — Reading What The Analyzer Says](./course-02-reading-analyzer-messages.md).

Before you can trust a tool that finds configuration errors, you need to know precisely which errors were *already* impossible to catch. This part follows a `kubectl apply` through the stages it actually passes through, shows where Istio gets a say and where it does not, and explains why a reference to a non-existent subset sails through all of it.

## One apply, four stages

When you run `kubectl apply -f virtualservice.yaml`, the object does not go straight into storage. It crosses the API server in a fixed order, and each stage can reject it for different reasons:

```text
  kubectl apply
       │
       ▼
  1. AUTHENTICATION / AUTHORIZATION   who are you, may you write here?
       │
       ▼
  2. MUTATING ADMISSION               webhooks that may rewrite the object
       │                              (this is where sidecar injection happens, for Pods)
       ▼
  3. SCHEMA VALIDATION                does it match the CRD's OpenAPI schema?
       │                              required fields, types, enums
       ▼
  4. VALIDATING ADMISSION             webhooks that may reject, not rewrite
       │                              istiod's `validation.istio.io` runs here
       ▼
     etcd                             stored. `kubectl apply` prints "created".
```

Stage 3 is Kubernetes' own work, done from the CustomResourceDefinition Istio installed. It knows that `spec.http` is a list and that `weight` is an integer. It has no idea what a subset is.

Stage 4 is Istio's own work. `istiod` runs an admission webhook that applies Istio's semantic rules to **the object being submitted** — and this is the stage people overestimate.

## What the validating webhook can and cannot see

The webhook receives one `AdmissionReview` containing the object under consideration. That is the whole input. It does not get the rest of the cluster, and it is not allowed to go and fetch it — an admission webhook is on the critical path of every write and must answer in milliseconds.

So the rule that follows is not an oversight, it is structural:

> A validating webhook can only check facts that are true or false **inside a single document**.

That splits Istio's mistakes into two classes with completely different detection stories:

| Class | Example | Caught at admission? |
| --- | --- | --- |
| **Intra-object** | `weight: 60` twice, so the route weights sum to 120 | **Yes** — the webhook has everything it needs |
| **Intra-object** | a misspelled field, a bad enum value, an invalid duration | Yes, usually at stage 3 |
| **Cross-object** | a `VirtualService` naming `subset: v3` that no `DestinationRule` defines | **No** — the `DestinationRule` is a different object |
| **Cross-object** | a `gateways:` entry naming a `Gateway` that does not exist | No |
| **Environmental** | a namespace carrying mesh config without an injection label | No |

The intra-object case is worth seeing once, because it proves the webhook is genuinely working rather than absent.

> [!TIP]
> **Try it — the webhook rejecting something it can see**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: bad-weights
>   namespace: analyze-demo
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
> Read who is speaking: `admission webhook "validation.istio.io"` — that is `istiod`, refusing at stage 4. Everything needed to reach that verdict was inside the document, so the webhook could reach it without consulting anything else.

Now the contrast. The namespace already contains a `VirtualService` that names a subset nothing defines, and it was accepted by every one of those four stages.

> [!TIP]
> **Try it — the configuration that passed all four stages and does not work**
>
> ```sh
> kubectl -n analyze-demo get virtualservice,destinationrule
> kubectl -n analyze-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://notification-service/notify
> ```
>
> Expect something like:
>
> ```text
> NAME                                              GATEWAYS              HOSTS                      AGE
> virtualservice.networking.istio.io/notification   ["missing-gateway"]   ["notification-service"]   4m
>
> NAME                                               HOST                   AGE
> destinationrule.networking.istio.io/notification   notification-service   4m
>
> 503
> ```
>
> Both objects exist, neither is marked unhealthy, and the request fails. Istio's networking resources have no `status` conditions that turn red — nothing in `kubectl` will ever tell you this pair is incoherent. The `503` is the only signal, and it names nothing. The exact ages vary.

## What istiod does with the object later

The object is now in etcd, and a second, entirely separate process begins. `istiod` watches the API server, holds the **whole** configuration set in memory, and converts it into Envoy configuration to push to proxies.

At that point the cross-object questions finally become answerable, because now there is a complete picture:

```text
  etcd ──watch──▶  istiod's in-memory config store
                        │   every VirtualService, DestinationRule, Gateway,
                        │   ServiceEntry, Service, Pod, ...
                        ▼
                   translation to Envoy xDS resources
                        │   "route to subset v3" → cluster outbound|80|v3|...
                        ▼
                   does that cluster exist?  ── no ──▶ the route points at nothing
```

Nobody is notified when that goes wrong. `istiod` is not in a request/response relationship with you any more — your `kubectl apply` returned successfully minutes ago. The consequence of a dangling reference is simply that the proxies receive configuration that cannot work.

## What an analyzer is

`istioctl analyze` closes the loop by doing, on demand, what `istiod` does continuously: it loads the whole configuration set and runs a collection of **analyzers** over it.

An analyzer is a small, single-purpose check with a declared list of resource kinds it wants to see. One analyzer knows how to walk every `VirtualService`, collect the subsets its routes name, and compare them against the subsets every `DestinationRule` defines. Another compares `gateways:` entries against existing `Gateway` objects. Another looks for namespaces carrying mesh configuration with no injection label.

Three properties follow from that design, and all three matter in practice:

- **It is a snapshot, not a watch.** Results describe the cluster at the moment you ran it. Re-run after every change.
- **It sees whatever you give it.** The configuration set can come from the cluster, from files, or from both — which is what [Part 3](./course-03-analysis-sources-and-the-fix-loop.md) is about.
- **It is scoped to a namespace by default.** Analyzers run over the objects in scope; a cross-namespace relationship with only one end in scope can produce a finding that looks wrong until you widen it.

Running it on the namespace you just inspected produces, in one command, the diagnosis that four admission stages could not reach.

> [!TIP]
> **Try it — the first real diagnosis**
>
> ```sh
> istioctl analyze -n analyze-demo
> ```
>
> Expect something like:
>
> ```text
> Error [IST0101] (VirtualService notification.analyze-demo) Referenced host+subset in destinationrule not found: "notification-service+v3"
> Error [IST0101] (VirtualService notification.analyze-demo) Referenced gateway not found: "missing-gateway"
> Error: Analyzers found issues when analyzing namespace: analyze-demo.
> See https://istio.io/v1.30/docs/reference/config/analysis for more information about causes and resolutions.
> ```
>
> Two commands ago you had a `503` and no suspect. Now you have the object, the fields, and the exact values that do not resolve — both of them cross-object references, which is exactly the class stage 4 was structurally unable to check.

> [!WARNING]
> **The pitfall this part exists to kill**
>
> **Treating a clean `kubectl apply` as proof the configuration is correct.** It proves the document matched a schema and satisfied every rule that can be evaluated without looking at another object. Every broken reference in this module applied without a word of complaint, and the same is true of the most expensive Istio outages: nothing was invalid, and nothing worked.

> *The API server validates one document; istiod evaluates the whole set — and only the second can see a reference that does not resolve.*

## Reference

- `istioctl analyze --help` — the flag list, including the scoping and threshold flags Parts 2 and 3 use.
- [Using the analyzer](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-analyze/) — Istio's own guide to the command, including how to run it against a directory of manifests.
- [Kubernetes admission controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/) — the stage model above, from the API server's side; worth reading once to see why webhooks are kept cheap.
- [Dynamic admission control](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) — the `AdmissionReview` payload a validating webhook actually receives, which is the concrete form of "it only sees one object".
