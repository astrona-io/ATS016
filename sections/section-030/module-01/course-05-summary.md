# Summary

A broken control plane does not look like an outage. Requests keep succeeding, and what stops is change. This module showed how to check `istiod` directly instead of trusting working traffic.

## What you learned

`istiod` does four jobs in one process. It is the xDS server that sends configuration to every sidecar proxy, and the certificate authority that signs workload certificates, both on port `15012`. It also serves the injection webhook and the validation webhook on port `15017`. The proxies call `istiod` for the first two jobs, and the API server calls it for the other two. Without `istiod`, running proxies keep their configuration and certificates, so traffic flows but nothing can change. Certificates last 24 hours by default and are renewed at half their lifetime, so a long outage breaks mutual TLS everywhere at once, long after it started.

The pod status says little about health. `istiod`'s only probe is a readiness check on port `8080`, and it only asks whether the server answers. A climbing `RESTARTS` count on a `Running` pod is a crash loop, often `OOMKilled`. The log records each push, and `reject`, `error` and `warn` lines are worth a search. The metrics on port `15014` include `pilot_xds_pushes`, `pilot_total_xds_rejects`, `pilot_total_xds_internal_errors` and `pilot_proxy_convergence_time`. Counters only go up, reset on restart, and are missing until their first increase.

With `istiod` scaled to zero, an existing request still returned `200`, but a restarted Deployment could not create its new pod. The injection webhook's `failurePolicy: Fail` refused the pod because the API server could not reach `istiod`. With `Ignore`, the pod would have started with no sidecar, outside the mesh. Scaling `istiod` back up was enough for the mesh to catch up by itself.

An invalid object can still be stored when the validation webhook is skipped, and a proxy can refuse configuration with a NACK. In both cases `kubectl get` and `kubectl describe` show nothing wrong. The key facts to remember are these:

- Working traffic proves nothing about the control plane; test a change instead.
- The `istiod` log, `pilot_total_xds_rejects` and `istioctl analyze` record configuration that was stored but never applied.
- A missing counter means zero, and only the difference between two readings is meaningful.
- Check in order: pod status, log, metrics, a small test change, then `istioctl proxy-status`.

<!-- astrona:playground:destroy -->
