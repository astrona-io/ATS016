# Overview: Check Control Plane Health (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH.
- The injected namespace **`cphealth-demo`**, containing
  `notification-service-v1` behind the Service `notification-service` on port
  80, and a `tester` client pod with `curl`.
- A **healthy control plane**. Nothing is broken on arrival — this environment
  exists so you can break `istiod` yourself and watch which half of the mesh
  notices.

Scaling `istiod` to zero here is safe: the cluster is yours and disposable.
The same command on a shared cluster stops injection, certificate issuance and
every configuration change for every team using the mesh.

## Things to try

- Record `pilot_xds_pushes` from `localhost:15014/metrics`, change something
  trivial (add a label to the Service), and read the counters again.
- Scale `istiod` to zero, then apply a `VirtualService` and watch whether the
  validation webhook still refuses it. Scale back up and check the `istiod` log
  for what happened to the object afterwards.
- Set the sidecar injector webhook's `failurePolicy` to `Ignore`, take `istiod`
  down, and create a pod. Compare the result with the default `Fail` behaviour.
- Lower `istiod`'s memory limit until it is `OOMKilled`, then watch the restart
  count climb while traffic keeps flowing.
- Delete a workload's certificate secret or restart a pod during the outage and
  observe how far the mesh gets without a CA.
