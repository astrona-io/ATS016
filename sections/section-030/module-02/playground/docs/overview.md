# Overview: Diagnose Configuration Sync With proxy-status (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH.
- The injected namespace **`proxysync-demo`**, containing
  `notification-service-v1` behind the Service `notification-service` on port
  80, and a `tester` client pod with `curl`.
- A **healthy, fully synced mesh**. Every proxy starts `SYNCED` on every xDS
  type; making one stop is up to you.
- `manifests/broken-config.yaml` — a `NetworkPolicy` that cuts the workload off
  from `istiod` on port 15012. It is included for reference and **will not take
  effect here**: the default `kind` CNI (`kindnetd`) does not enforce
  `NetworkPolicy`. Apply it on a cluster running Calico or Cilium to see a
  `2/2` pod vanish from `proxy-status`.

## Things to try

- Remove the namespace injection label, restart the Deployment, and watch the
  row disappear from `istioctl proxy-status` while the pod stays `Running`.
- Apply a `VirtualService`, then immediately run `istioctl proxy-status` in a
  loop and try to catch a `STALE` before it settles.
- Run `istioctl proxy-status deploy/tester.proxysync-demo` and read the
  per-resource comparison.
- Scale `istiod` to zero and see what `proxy-status` itself does when the
  control plane it queries is gone.
- Compare `istioctl version` with the per-proxy `VERSION` column, then imagine
  what the same comparison would show mid-upgrade.
