# Overview: Troubleshoot With Kiali (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH.
- The **Prometheus and Kiali addons** from the Istio 1.30 release, in
  `istio-system`. Kiali needs both; it is a view, not a data source.
- The injected namespace **`kiali-demo`**, containing
  `notification-service-v1` behind the Service `notification-service` on port
  80, and a `tester` client pod with `curl`.
- Two manifests to apply when you want them:
  - `fault.yaml` — aborts 30% of requests with a `500`, which turns the graph
    edge red.
  - `broken-config.yaml` — a `VirtualService` with a missing gateway and a
    missing subset, for the Istio Config validation view.

No traffic is flowing at startup, so the graph is empty. That is the correct
starting state and the first thing the module has you fix.

## Reaching the dashboard

```sh
kubectl -n istio-system port-forward svc/kiali 20001:20001
```

Then open `http://localhost:20001` in a browser that can reach this machine.
Whether that works depends on how you are connected to the playground; every
exercise in the module also has a command-line form.

## Things to try

- Look at the graph with no traffic, then with traffic, and note how long an
  edge persists after the load stops.
- Apply `fault.yaml` and watch the edge change colour, then compare the
  percentage Kiali shows against the raw counters on the proxy.
- Apply `broken-config.yaml` and find it in Istio Config, then confirm the same
  findings with `istioctl analyze -n kiali-demo`.
- Remove the namespace injection label, restart, and watch the workload vanish
  from the graph while remaining in the Workloads list.
- Turn on the Security display and confirm the padlock against
  `connection_security_policy` in the destination proxy's metrics.
