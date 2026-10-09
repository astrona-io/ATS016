# Summary

A pod without a sidecar proxy is not in the mesh, and no policy applies to it. Kubernetes reports nothing wrong, so this module showed how injection works and how to find out why a pod was skipped.

## What you learned

Injection is one edit to a Pod at creation. During mutating admission, the API server checks the injection webhook's `namespaceSelector` and `objectSelector`. If they match, it calls `istiod` on port `15017`, and `istiod` answers with a JSONPatch that adds the `istio-proxy` container, the `istio-init` container that installs the `iptables` redirection, and the volumes for the token and the root certificate. On nodes with Kubernetes 1.33 or later, Istio 1.30 adds the proxy as a native sidecar under `initContainers`. Nothing ever adds a sidecar to an existing pod, the Deployment never contains it, and the webhook's `failurePolicy` decides what an `istiod` outage does to new pods.

Two independent checks show whether a pod is in the mesh: its container count, and a row in `istioctl proxy-status`. `istioctl analyze` reports `IST0103` only for pods that lack a proxy without opting out, so it stays silent about a deliberate opt-out. A namespace asks for injection with `istio-injection=enabled` or `istio.io/rev=<revision>`, and the webhook entries decide who wins. The pod template's `sidecar.istio.io/inject: "false"` beats everything, `istio-injection=enabled` beats `istio.io/rev`, and a pod can opt in on its own only when its namespace has no injection label.

The checklist runs in a fixed order: namespace label, pod template label, pod age, webhook health, revision, pod spec. A pod-template fix recreates pods by itself; a namespace label, webhook or revision fix needs a restart. The key facts to remember are these:

- The opt-out label only works in `spec.template.metadata.labels`, never in the Deployment's own labels.
- A namespace that matches no webhook entry leaves no trace: no call, no log, no error.
- A namespace pinned to a revision or tag that does not exist is never injected.
- A workload has joined when the sidecar is in the pod, its row is `SYNCED`, and a real request still returns `200`.

<!-- astrona:playground:destroy -->
