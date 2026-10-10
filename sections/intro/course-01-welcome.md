# Welcome To The Course

This course trains you for the **Troubleshooting** part of the **Istio Certified Associate (ICA)** exam. That part is 20% of the exam. This page tells you who the course is for, what you can do at the end, which words and example app it uses, and how its pages fit together.

## Who this course is for

You know your way around Kubernetes: namespaces, Deployments, Services, pod labels, `kubectl logs` and `kubectl exec`. You have seen the basic Istio routing objects, `VirtualService` and `DestinationRule`, even if you do not use them every day. You do not need to be an Istio expert. Each new idea is explained the first time it appears.

## What you can do at the end

The exam is hands-on. You get a live cluster and a list of tasks, and you have to make broken things work. So this course does not ask you to remember words. It asks you to find the cause of a failure, fix it, and prove the fix with a real request. The exam groups this part into three topics, and each one turns into a set of skills you will practise.

The first topic is **troubleshooting configuration**: Istio objects that the cluster accepted but that do not do what you meant. You will learn to:

- Find references that point at nothing with `istioctl analyze`, and read its `IST####` messages.
- See every Istio object that applies to one pod with `istioctl x describe pod`.
- Find two `VirtualService` objects that claim the same host, and route rules that can never match.
- Collect the state of a cluster with `istioctl bug-report` to hand a problem to someone else.

Configuration only works if Istio's control plane delivers it, so the second topic is **troubleshooting the mesh control plane**. You will learn to:

- Check that `istiod` is healthy, and read its logs and metrics.
- Find out with `istioctl proxy-status` whether every proxy holds the latest configuration.
- Find out why a pod has no sidecar proxy, and fix sidecar injection.

The third topic is **troubleshooting the mesh data plane**: the proxies that carry each request. You will learn to:

- Read the listeners, routes, clusters and endpoints a proxy really holds with `istioctl proxy-config`.
- Find the cause of a `503` from the proxy's own configuration.
- Read an Envoy access log line and its response flag, the short code that says why a request failed.
- Find a mutual TLS (mTLS) mismatch between two workloads.
- Measure a failure with Prometheus, Grafana and Kiali, and prove a fix with the same numbers.

Everything is built and checked on **Istio 1.30.5**.

## The words this course uses

The pages use Istio's, Envoy's and Kubernetes' own terms, because those are the words you meet in the product, the logs and the exam. Each term gets a short, plain definition the first time it appears on a page. A few terms come back on almost every page, so here they are up front.

A **pod** runs one copy of an application, and a **namespace** groups pods and other objects inside the cluster. A **request** is one call that a client sends to a server, and the **response** is the answer it gets back. The **sidecar proxy** (Envoy) is a proxy container that Istio adds to each pod; all traffic in and out of the pod passes through it. **`istiod`** is Istio's control plane. It turns Istio objects into proxy configuration and sends it to every proxy over **xDS**, the protocol for pushing configuration to proxies while they run.

The proxy's configuration has four kinds of objects, and you will read all of them:

| Envoy object | What it does |
| --- | --- |
| Listener | Accepts traffic on an address and port |
| Route | Picks a destination for an HTTP request, by host, path or header |
| Cluster | A named group of upstream endpoints, for example one subset of a Service |
| Endpoint | The IP address and port of one pod in a cluster |

## The example app in your playground

Every playground and lab runs the same small app. The Service `notification-service` sits in front of one or two nginx Deployments, `notification-service-v1` and `notification-service-v2`, which answer with a short JSON body. You send your test requests from the `tester` pod, a client with `curl`. A few modules add a second backend, `reporting-service`, an HTTP echo server.

Each module puts the app in its own namespace, for example `analyze-demo` or `mtlsfail-demo`, so the pages always tell you the namespace to use. Many playgrounds and labs start with something broken on purpose. That is the material, not a fault in the course.

## How the course is laid out

The course has six sections, in the order of an investigation: first the configuration, then the control plane, then the proxies, and last the metrics.

| Section | What it covers |
| --- | --- |
| 010 | Troubleshooting Configuration With istioctl |
| 020 | Debugging Conflicting And Shadowed Routes |
| 030 | Troubleshooting The Mesh Control Plane |
| 040 | Reading Data Plane Configuration |
| 050 | Debugging Data Plane Request Failures |
| 060 | Troubleshooting With Mesh Observability |

Each section has one or more **modules**, and each module teaches one skill. A module brings together four kinds of material:

| What | What it is for | Graded? |
| --- | --- | --- |
| **Reading** | A short landing page, a few chapters that teach one idea each, and a summary | No |
| **Playground** | A small cluster on your own machine, to try everything you read | No |
| **Lab** | A broken cluster, a task, and a grader that checks your fix | Yes |
| **Capstone** | The last lab in a section, with several faults at once | Yes |

The best order is simple: read the chapters with the playground open next to them, take each lab when a chapter sends you to it, and finish each section with its capstone. The next part of this page explains how a module's pages guide you through that order.

## How to read a page

A module starts with a **landing page**. It says what the module teaches, what you should know first, and the order of its chapters. At the bottom of the landing page you start the module's playground, and you keep it running while you read.

The chapters (the parts of a module) read like the chapters of a technical book. Each one opens with the problem it solves, explains one idea in connected paragraphs, and closes with what you now know. The hands-on steps sit right in the text: a sentence or two on what to run and why, the command, the real output, and then what that output shows. Run each step in your playground as you reach it. You learn more from one real result than from a page of text.

Every chapter ends with a box of common pitfalls, the mistakes people make most often with what the chapter taught, and how to spot them. Now and then a page also has a tip box with a habit or shortcut you can use again, well beyond that page. The two boxes look like this:

> [!TIP]
> **A tip.** A habit or shortcut you can use again, well beyond this one page.

> [!WARNING]
> **Common pitfalls.** The mistakes people make most often with what you just learned, and how to spot them. Every chapter ends with one.

When a graded lab tests what a chapter taught, that chapter ends with a **Your mission** section. It tells you what the lab asks, then gives every command you need, in order: pause the playground with `astrona stop`, start the lab with `astrona run`, and send your work for grading with `astrona submit`. Solve the lab on your own before you look at its solution. When the lab is done, remove it with `astrona destroy` and start the playground again with `astrona start`, so you can carry on reading where you left off.

The last page of every module is the **Summary**. It sums up what you learned in a few short paragraphs, organised by idea. It also ends the module's hands-on work: the Summary page removes the playground, so your machine is clean before the next module.

One rule holds on every page. Code blocks are exactly what you type or what you will see. Never change a command to make it "look right". If the result is different from the page, that difference is the lesson.
