# Prerequisites

Before starting this lab you should be able to:

- Send a PromQL query to Prometheus over its HTTP interface with `curl`.
- Write a rate grouped by a label, and an error ratio, over `istio_requests_total`.
- Explain the `reporter` label and the `response_flags` label.
- Read and edit a `VirtualService`.

## What the environment gives you

The lab environment builds itself before the task begins:

- A single-node `kind` Kubernetes cluster, with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH.
- The **Prometheus** add-on in `istio-system`, reachable inside the cluster at
  `http://prometheus.istio-system:9090`.
- The namespace **`callers-demo`**, prepared as the task describes. Traffic
  already flows when the lab starts.

Nothing the task asks you to create has been created for you.

## Working rules

- Everything is graded on the **final cluster state**, so leave the ConfigMap
  and the fixed `VirtualService` in place.
- Measure before you change anything. Once the fault is gone, the error rates
  fall to zero and the evidence fades from the one-minute window.
- `kubectl`, `istioctl` and `curl` are available. No internet access is needed
  once the environment is up.
