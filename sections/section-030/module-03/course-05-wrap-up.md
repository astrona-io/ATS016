# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the launch-pad crew: the injection webhook that puts a communications officer (sidecar proxy) on board each new ship, and the checklist for when it did not.

**From [How Injection Actually Happens](./course-01-the-injection-webhook.md):**

- Injection is one edit to a Pod, made by the mutating admission webhook while the API server holds the request. `istiod` answers on port `15017` with a JSONPatch.
- The patch adds `istio-proxy`, `istio-init` (or the Istio CNI plugin does that work) and supporting volumes.
- It happens at pod creation only, it changes the Pod and never the Deployment, and it needs `istiod` to answer at that moment.
- Two checks find a pod with no sidecar: count the containers, and look for `IST0103` (only `Info`) in `istioctl analyze`.

**From [Labels, Selectors And Precedence](./course-02-labels-and-precedence.md):**

- A namespace asks for injection with `istio-injection=enabled` (default revision) or `istio.io/rev=<revision>`.
- The webhook's `namespaceSelector` and `objectSelector` are the real rule; a namespace that matches no entry is never even asked about.
- `sidecar.istio.io/inject: "false"` only works on the pod template, and it beats every namespace setting.
- If both namespace labels are present, `istio-injection=enabled` wins and the revision label is ignored.

**From [Working The Checklist](./course-03-working-the-checklist.md):**

- Check in order: namespace label, pod template label, pod age, webhook health, revision, pod spec.
- A label change is not finished until the pods are recreated.
- A namespace tied to a revision or tag that no longer exists gets no injection at all; `istioctl tag list` shows the broken link.
- `hostNetwork: true` pods are never injected.

**From [Fix It And Prove It Joined](./course-04-fix-and-prove.md):**

- The JSON Patch path writes the `/` in the label key as `~1`.
- Patching the pod template recreates the pods by itself; a namespace label fix needs `kubectl rollout restart`.
- Prove the join twice: the `istio-proxy` container exists, and the row is `SYNCED` in `istioctl proxy-status`.
- Then send a real request, because interception can expose an unnamed port or a loopback-only listener.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Bring An Exempt Workload Back Into The Mesh](./labs/lab-01/README.md) | Fix It And Prove It Joined | find a pod-template opt-out, remove it without touching the namespace labels, and prove the workload joined and still serves traffic |

If you skipped it, go back to it now.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. You add <code>istio-injection=enabled</code> to a namespace. Its pods still show <code>1/1</code>. Why?</summary>

Injection only happens when a pod is created. The pods existed before the label. Recreate them, for example with `kubectl rollout restart deployment`.
</details>

<details>
<summary>2. Why will <code>kubectl get deployment -o yaml</code> never show <code>istio-proxy</code>?</summary>

The webhook edits the Pod object, not the Deployment. The Deployment's pod template never contains the sidecar.
</details>

<details>
<summary>3. A team put <code>sidecar.istio.io/inject: "false"</code> in the Deployment's own <code>metadata.labels</code>. Is the workload excluded?</summary>

No. Labels in the Deployment's own metadata are not copied to its pods. The opt-out only works in `spec.template.metadata.labels`.
</details>

<details>
<summary>4. A namespace has both <code>istio-injection=enabled</code> and <code>istio.io/rev=canary</code>. Which control plane injects its pods?</summary>

The default revision. `istio-injection=enabled` wins and the revision label is ignored. Remove the old label when you add the revision label.
</details>

<details>
<summary>5. A namespace is labelled <code>istio.io/rev=1-25</code>, the webhook exists, and no pod is ever injected. What do you check?</summary>

Whether that revision is still installed: `kubectl -n istio-system get pods -l app=istiod -L istio.io/rev` and `istioctl tag list`.
</details>

<details>
<summary>6. You remove an opt-out from a pod template with <code>kubectl patch</code>. Do you also need <code>kubectl rollout restart</code>?</summary>

No. Changing the pod template creates a new ReplicaSet and new pods by itself. A namespace label change is the case that needs the restart.
</details>

<details>
<summary>7. The new pod has an <code>istio-proxy</code> container. Is the job done?</summary>

Not yet. Confirm the proxy connected with `istioctl proxy-status`, and send a real request to prove the application still answers.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-030-03
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-016-lab-030-03
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time from the module's landing page. It always starts clean, so nothing you broke carries over.

> *No officer on board means no mesh: count the containers, work the checklist, and prove the join twice.*
