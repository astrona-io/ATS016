# Find Configuration Errors With istioctl analyze

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS016/tree/main/sections/section-010/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-01/playground
> astrona destroy ats-016-playground-010-01
> ```

A `VirtualService` that routes to a subset nobody ever defined applies cleanly. `kubectl get` lists it. `kubectl describe` shows no events worth reading. The only visible symptom is that requests return `503`, several layers away from the object that caused it.

That gap — between configuration the Kubernetes API server accepts and configuration that actually means something to Istio — is what this module is about. The boundary worth holding on to is this: **`kubectl apply` validates one document at a time, and `istioctl analyze` validates a configuration set.** Almost every confusing mesh problem lives in the space between those two sentences.

> analyze reads the config the way istiod does, so it finds the mistakes the API server happily accepted.

## How this module is organised

1. **[Part 1 — What The API Server Checks, And What It Cannot](./course-01-admission-and-the-analysis-gap.md)** — the admission path a `kubectl apply` actually takes, why a validating webhook cannot catch a missing subset even in principle, and what an analyzer is.
2. **[Part 2 — Reading What The Analyzer Says](./course-02-reading-analyzer-messages.md)** — severity, `IST####` code and blamed object; the codes worth memorising; JSON output; and the exit-code behaviour that makes this a CI gate.
3. **[Part 3 — Choosing The Right Analysis Source](./course-03-analysis-sources-and-the-fix-loop.md)** — cluster, file-on-top-of-cluster, and file-alone; `validate` against `analyze`; and the discipline of fixing one thing and proving it twice.

## Learning objectives

After this module you can:

- Describe the stages a `kubectl apply` of an Istio resource passes through, and name which stage rejects what.
- Explain why cross-object references cannot be validated at admission time, and what that implies for your own manifests.
- Run `istioctl analyze` against a namespace, the whole mesh, and a file that has not been applied yet.
- Read an analyzer message and name its severity, its `IST####` code, and the object it blames.
- Explain why a `Warning` is often the real cause of a "my configuration does nothing" report.
- Use `--failure-threshold` and the command's exit code to make analysis a build gate.
- Choose between `istioctl validate` and `istioctl analyze` for a given situation, and state what each cannot see.
- Fix an analyzer `Error` and prove the fix with both a clean analyze run and real traffic.

## Before you start

You should be comfortable with `kubectl`, and know what a `VirtualService` and a `DestinationRule` are for — this module does not teach routing, it teaches how to find out that your routing is broken.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the namespace **`analyze-demo`**, injected, containing:

- `notification-service-v1` — a Deployment labelled `version: v1`, behind a Service `notification-service` on port 80.
- `tester` — a client pod with `curl`.
- A `DestinationRule` and a `VirtualService` that **are already broken on purpose**. Finding out how is the module's subject, so do not read the manifests in `playground/manifests/` until you have run the analyzer yourself.

Every command in every part runs against the playground cluster; `kubectl` is already pointed at it.

## Where this fits

Analysis is the first of three questions in any mesh investigation, and the order matters because each one only makes sense if the previous answer was yes:

1. **Is the configuration coherent?** → `istioctl analyze` — this module
2. **Did it reach the proxies?** → `istioctl proxy-status` ([section 030](../../section-030/module-02/course.md))
3. **What is the proxy actually doing with it?** → `istioctl proxy-config` ([section 040](../../section-040/module-01/course.md))

Working outside-in keeps you from reading a 4,000-line Envoy configuration dump to discover a typo the analyzer would have named in two seconds. It also keeps you honest in the other direction: a clean analyze run does not end the investigation, it moves it to question two.
