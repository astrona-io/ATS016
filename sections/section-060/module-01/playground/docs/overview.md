# Overview: Troubleshoot With Kiali (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs `bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What is in the box

- A single-node `kind` Kubernetes cluster (your training solar system) with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your PATH.
- The **Prometheus and Kiali add-ons** from the Istio 1.30 release, in `istio-system`. Kiali, the tactical map, needs both: it draws what others record, it does not collect data itself.
- The injected namespace **`kiali-demo`**, containing `notification-service-v1` behind the Service `notification-service` on port `80`, and a `tester` client pod with `curl`.

No traffic flows at startup, so the graph is empty. That is the correct starting state, and the first thing the module has you fix.

The course pages give you the YAML for the two experiments in this module: a `VirtualService` that aborts 30% of requests with a `500` (it turns the graph edge red), and a `VirtualService` that names a missing gateway and a missing subset (it shows up in the Istio Config validation view). Save each one to a file and apply it with `kubectl apply -f`.

## Reaching the dashboard

```sh
kubectl -n istio-system port-forward svc/kiali 20001:20001
```

Then open `http://localhost:20001` in a browser that can reach this machine. Whether that works depends on how you are connected to the playground. Every exercise in the module also has a command-line form.

## Things to try

- Look at the graph with no traffic, then with traffic, and note how long an edge stays after the load stops.
- Apply the 30% fault and watch the edge change colour. Then compare the percentage Kiali shows with the raw counters on the proxy.
- Apply the broken `VirtualService` and find it in Istio Config. Then confirm the same findings with `istioctl analyze -n kiali-demo`.
- Remove the namespace injection label, restart the workloads, and watch the workload vanish from the graph while it stays in the Workloads list.
- Turn on the Security display and confirm the padlock against `connection_security_policy` in the destination proxy's metrics.
