# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the gap between configuration the registry office accepts and configuration that works, and about the pre-flight inspector that closes it: `istioctl analyze`.

**From [What The API Server Checks, And What It Cannot](./course-01-admission-and-the-analysis-gap.md):**

- A `kubectl apply` passes four stages: authentication and authorization, mutating admission, schema validation, and validating admission. Istio's `validation.istio.io` webhook runs at the last stage.
- The validating webhook only sees the one document being filed. It catches weights that add up to 120, but never a subset or gateway that another object should define.
- `istiod` reads the whole configuration set later, and nobody is told when a reference points at nothing. A `503` is often the only symptom.
- `istioctl analyze` loads the whole set on demand and runs analyzers over it. It is a snapshot, and it looks at one namespace by default.

**From [Reading What The Analyzer Says](./course-02-reading-analyzer-messages.md):**

- Every finding has a severity, an `IST####` code, an origin and a message. Search by the code; the message text changes between releases.
- Severity says what Istio will do, not how urgent it is. Warnings such as `IST0102` often explain "my policy does nothing".
- `-o json` adds a documentation address for each code and makes the output scriptable.
- The default `--failure-threshold` is `Error`, so Warnings do not fail the command. Choose the threshold on purpose in a pipeline.

**From [Choosing The Right Analysis Source](./course-03-analysis-sources-and-the-fix-loop.md):**

- Analyze the cluster, a file on top of the cluster, or a file alone with `--use-kube=false`. Each answers a different question.
- `istioctl validate` checks one document and passes every mistake between objects.
- Fix a broken reference in the direction that matches reality. Never invent a subset that matches no pod.
- Change one thing, then prove it twice: a clean analyze run and a real request. Widen to `--all-namespaces` before you call the mesh healthy.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Find And Fix The Configuration Errors](./labs/lab-01/README.md) | Choosing The Right Analysis Source | find two references that point at nothing, fix them in the right direction, and prove it with a clean analyze run and ten `200` responses |

If you skipped it, go back to it now. It is short.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. A <code>VirtualService</code> names a subset that no <code>DestinationRule</code> defines. Why did <code>kubectl apply</code> accept it?</summary>

The validating webhook only sees the one document being filed. Whether a subset exists depends on a different object, the `DestinationRule`, so no admission stage can check it.
</details>

<details>
<summary>2. Two route weights of 60 are rejected at apply time. Which component refuses them?</summary>

`istiod`, through its `validation.istio.io` admission webhook. Everything it needs to see the weights add up to 120 is inside the one document.
</details>

<details>
<summary>3. What are the four parts of an analyzer finding?</summary>

The severity (`Error`, `Warning` or `Info`), the `IST####` code, the origin (the object being blamed), and the message text.
</details>

<details>
<summary>4. Why can a <code>Warning</code> be more serious than an <code>Error</code>?</summary>

Severity describes what Istio will do with the object, not how much harm it causes. `IST0102`, a Warning, means a namespace has no injection label, so every policy in it applies to nothing.
</details>

<details>
<summary>5. Your pipeline runs <code>istioctl analyze</code> and passes, but the namespace has an <code>IST0102</code> Warning. Why?</summary>

The default `--failure-threshold` is `Error`, so Warnings do not change the exit code. Set `--failure-threshold Warning` to fail on them.
</details>

<details>
<summary>6. <code>istioctl validate -f file.yaml</code> says <code>validation succeed</code>, but <code>istioctl analyze --use-kube=false file.yaml</code> reports <code>IST0101</code>. Which one is right?</summary>

Both. `validate` only checks that the document is well formed. `analyze` checks the objects together and finds the subset that nothing defines.
</details>

<details>
<summary>7. The analyzer reports a missing subset <code>v3</code>, and only <code>version: v1</code> pods run. Why not just add a <code>v3</code> subset?</summary>

A subset whose labels match no pod becomes a cluster with no endpoints. The analyzer goes quiet, and traffic still fails, just with a less clear error. Route to `v1` instead.
</details>

<details>
<summary>8. <code>istioctl analyze</code> is clean, and requests still return <code>503</code>. What does that tell you?</summary>

The configuration is coherent, but it may not have reached the proxies, or the problem lies elsewhere. Move on and ask `istioctl proxy-status` whether every proxy holds the latest configuration.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-010-01
```

If `astrona list` also showed the mission, remove it the same way:

```sh
astrona destroy ats-016-lab-010-01
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with `astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-01/playground`. It always starts clean, so nothing you broke carries over.

> *The registry clerk checks each form; the pre-flight inspector checks how the forms fit together. Ask the inspector first.*
