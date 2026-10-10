# Summary

Istio configuration can be accepted by the cluster and still not work. This module showed why that gap exists and how `istioctl analyze` closes it.

## What you learned

A `kubectl apply` passes four stages in the API server: authentication and authorization, mutating admission, schema validation against the CRD, and validating admission. At the last stage, `istiod` runs the `validation.istio.io` webhook. That webhook sees only the one object being applied. It rejects mistakes inside one document, such as one HTTP rule with both `redirect` and `route`. It can never reject a reference to another object, such as a subset or a gateway that does not exist. Istio networking resources have no status that reports a problem, so a `503` is often the only symptom.

`istiod` later reads the whole configuration set and turns it into Envoy configuration, but it reports nothing back when a route points at nothing. `istioctl analyze` gives you that complete view on demand. It loads the whole set, runs analyzers over it, and prints one message per problem. It is a snapshot, and it reads one namespace unless you pass `-n` or `--all-namespaces`.

Every analyzer message has a severity, an `IST####` code, an origin that names the object, and a message text. Search by the code, because the text changes between releases. The severity says what Istio will do with the object, not how urgent the problem is. `IST0102` (`Info`) and `IST0103` (`Warning`) often explain "my policy does nothing", because they point at pods without a sidecar proxy. The default `--failure-threshold` is `Error`, so `Warning` and `Info` messages do not change the exit code unless you lower the threshold.

The analyzer can read the cluster, a file on top of the cluster, or a file alone with `--use-kube=false`. Each source answers a different question. A file on top of the cluster is the check before you apply: it caught the missing subset with a line number, while the file alone passed it. `istioctl validate` checks one document only, so it passes every mistake between objects. A broken reference is fixed in the direction that matches what is deployed. A subset whose labels match no pod only turns a clear failure into a `503` with `UH`. The key facts to remember are these:

- `kubectl apply` succeeding proves the document is valid, not that its references resolve.
- `IST0101` means a referenced host, subset, gateway or secret does not exist.
- Change one object, then prove the fix twice: a clean analyze run and a real request that returns `200`.
- A clean analyze run proves the configuration is coherent, not that it reached the sidecar proxies.

<!-- astrona:playground:destroy -->
