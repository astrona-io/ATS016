# Prerequisites

Before starting this lab you should be able to:

- Use `kubectl` to list pods and Deployments in a namespace.
- Run `istioctl bug-report` with `--include`, `--duration` and `--output-dir`.
- List the contents of a `.tar.gz` file with `tar tzf`.

## What the environment gives you

The lab environment builds itself before the task begins:

- A single-node `kind` Kubernetes cluster, with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, and `istioctl` on your PATH.
- The namespaces **`describe-demo`** and **`noise-demo`**, both with sidecar injection on, prepared as the task describes.

Nothing the task asks you to create has been created for you. There is no archive at `/tmp/ats-016-bug-report/` when the lab starts.

## Working rules

- Everything is graded on the archive at `/tmp/ats-016-bug-report/bug-report.tar.gz` and on the pods running when you submit. If you take a new capture, it replaces the old file.
- Do not restart or delete pods. The grader matches the pod name in the archive against the pod that is running.
- `kubectl`, `istioctl` and `tar` are available. No internet access is needed once the environment is up.
