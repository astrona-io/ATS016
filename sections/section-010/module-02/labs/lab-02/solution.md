# Solution: Capture A Limited bug-report Archive

Work the task yourself first. Running `astrona submit -c sections/section-010/module-02/labs/lab-02` after a step tells you which checks pass, without telling you what is left.

The grader reads the archive at `/tmp/ats-016-bug-report/bug-report.tar.gz` with `tar tzf` and checks three things: the file exists and can be listed, it holds the configuration dump of the running `notification-service-v1` pod and data for `istiod`, and no other proxy is in it.

## Step 1: See what a capture could pick up

An unlimited `bug-report` collects every sidecar proxy in the mesh. List the pods that have one, so you know what must stay out:

```sh
kubectl get pods -n describe-demo
kubectl get pods -n noise-demo
kubectl get deployments -n istio-system
```

`describe-demo` runs `notification-service-v1` and `tester`, and `noise-demo` runs its own `tester`; all three pods show `2/2`, so each has an `istio-proxy` container. `istio-system` runs `istiod` and the two gateways of the `demo` profile, `istio-ingressgateway` and `istio-egressgateway`. The gateways are Envoy proxies too, so an unscoped capture would include them.

## Step 2: Build the include filter

`--include` takes up to six fields separated by slashes: namespace, Deployment, pod, label, annotation, container. Each field can hold a comma-separated list. Do not pass `--include` twice: in Istio 1.30.5, repeated `--include` selectors are joined with AND, so `--include describe-demo/notification-service-v1 --include istio-system/istiod` matches nothing and the archive holds no proxy data. One selector with lists selects exactly what the task asks for:

- the namespaces `describe-demo,istio-system`;
- the Deployments `notification-service-v1,istiod`.

That matches `notification-service-v1` in `describe-demo` and `istiod` in `istio-system`, and nothing else: the `tester` pods and the two gateways belong to other Deployments. `istiod` is not collected automatically. Without `istio-system` and `istiod` in the selector, the archive has no control plane data.

## Step 3: Take the capture

Create the folder, then run the capture with a ten-minute log window. The capture takes a minute or two, because `istioctl` reads each selected proxy's administration port and runs `istioctl analyze` at the end:

```sh
mkdir -p /tmp/ats-016-bug-report
istioctl bug-report \
  --include describe-demo,istio-system/notification-service-v1,istiod \
  --duration 10m \
  --output-dir /tmp/ats-016-bug-report
```

The last line of the output names the archive it wrote, `/tmp/ats-016-bug-report/bug-report.tar.gz`. `--duration 10m` keeps the logs short; the grader does not check it, but a platform team will thank you for it.

## Step 4: Check the archive before you hand it over

List which pods the archive holds data for:

```sh
tar tzf /tmp/ats-016-bug-report/bug-report.tar.gz \
  | grep -E '^bug-report/(proxies|istio)/' | cut -d/ -f2-4 | sort -u
```

You should see two kinds of line: `istio/istio-system/` followed by the `istiod` pod name, and `proxies/describe-demo/` followed by the `notification-service-v1` pod name. If a `tester` pod, a `noise-demo` pod or a gateway appears, the filter is too wide: fix the `--include` selector and capture again. The new archive replaces the old file.

Then confirm the configuration dump of the proxy is there:

```sh
tar tzf /tmp/ats-016-bug-report/bug-report.tar.gz | grep 'proxies/describe-demo/.*/config_dump'
```

One line ending in `config_dump?include_eds` is the full Envoy configuration of the `notification-service` proxy, which is what the platform team needs to explain the `403`.

## Step 5: Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-010/module-02/labs/lab-02
```

## Why the shortcuts are wrong

| Shortcut | What happens |
| --- | --- |
| `istioctl bug-report` with no `--include` | every proxy in the mesh is collected, including `noise-demo` and both gateways |
| `--include describe-demo` | the `tester` proxy in `describe-demo` is collected too, and `istiod` is missing |
| `--include describe-demo/notification-service-v1` only | the proxy is right, but there is no control plane data |
| `--include istio-system` | both gateways are collected along with `istiod` |
| Restarting the pod before the capture | the pod name changes, and the evidence of the problem is lost |

## Common mistakes

- Expecting `istiod` in the archive without an `--include` that matches it.
- Forgetting `--output-dir`, so the archive lands in the current folder instead of `/tmp/ats-016-bug-report/`.
- Adding `--full-secrets`. Secret contents never belong in an archive you hand to another team.
- Handing over an archive without listing it first.
