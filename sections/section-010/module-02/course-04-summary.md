# Summary

When one workload behaves oddly, the question is what all the configuration around it adds up to, and how to prove it. This module covered three tools for that question: `istioctl x describe pod`, Envoy log scopes, and `istioctl bug-report`.

## What you learned

Istio objects find their targets in different ways. `VirtualService` and `DestinationRule` are matched by host and applied by the client's sidecar proxy. `PeerAuthentication` and `AuthorizationPolicy` are matched by pod labels and enforced by the server's sidecar proxy. For `PeerAuthentication`, the narrowest scope wins: a workload policy overrides a namespace policy, which overrides the mesh-wide one. Every `AuthorizationPolicy` that selects a workload applies together, checked as `CUSTOM`, then `DENY`, then `ALLOW`. An `ALLOW` policy denies every request that matches none of its rules, so a policy that allows only `POST` turns every `GET` into a `403` from the sidecar proxy.

`istioctl x describe pod` shows the effective result for one pod: its Service, the `AuthorizationPolicy` rules that select it, the routes and subsets that apply, and the effective mTLS mode. The warnings at the bottom often hold the answer, for example a Service port with no declared protocol or a policy that cannot take effect. It does not report problems across the cluster; `istioctl analyze` does that.

Envoy's administration interface on `localhost:15000` is behind `istioctl proxy-config`, and changes made through it are runtime state that a restart loses. Envoy logs in scopes, and every scope in a default Istio 1.30 sidecar starts at `warning`. Raising one scope, such as `rbac:debug`, on the receiving proxy makes it log each authorization decision. `enforced denied, matched policy none` means an `ALLOW` policy selected the workload and no rule matched, and `shadow` marks a dry-run policy.

`istioctl bug-report` freezes the state of `istiod` and selected proxies into `bug-report.tar.gz`, including each proxy's full configuration dump. It must be limited and handled with care. The key facts to remember are these:

- Limit a capture with `--include` and `--duration`; `istiod` is collected only when the `--include` selector matches it. Repeated `--include` flags are joined with AND, so put several namespaces and Deployments in one selector, for example `describe-demo,istio-system/notification-service-v1,istiod`.
- Proxy data sits under `bug-report/proxies/<namespace>/<pod>/`, and `istiod` data under `bug-report/istio/<namespace>/<pod>/`.
- Put a raised log scope back with `istioctl proxy-config log <pod> --level <scope>:warning`, and check it by running the command with no `--level`.
- Review an archive before you share it, and never share one taken with `--full-secrets`.

<!-- astrona:playground:destroy -->
