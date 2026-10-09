# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about flight plans (`VirtualService` objects) that are valid on their own and still send signals the wrong way.

**From [How A VirtualService Becomes A Route Table](./course-01-virtualservice-to-route-table.md):**

- `istiod` turns a `VirtualService` into a route configuration named after the port (`80`), with one virtual host per host and your `http` rules as an ordered list.
- The proxy checks the list from the top, and the first match wins. There is no ranking by how specific a rule is.
- A rule with no `match` becomes a prefix match on `/`, which is always true. Everything below it can never be reached, and nothing warns you.
- A rule with no effect at all is usually never reached; a rule that partly works usually has a wrong match.

**From [One Host, Two Owners](./course-02-host-ownership-and-merging.md):**

- Two `VirtualService` objects that claim the same host in the same gateway scope are merged into one list, in an order nobody controls.
- `istioctl analyze` reports this as `Warning [IST0109]`: valid, but undefined behaviour.
- The rule is one object per host per gateway scope. Binding objects to different gateways is the legitimate way to have two; delegation is the planned way to combine them.

**From [The Route Table Is The Ground Truth](./course-03-reading-the-route-table.md):**

- `istioctl proxy-config routes deploy/tester -n conflict-demo --name 80 -o json` shows what the client's proxy really holds, after every merge.
- The fix had two halves: delete the second claimant, then put the specific match first and the catch-all last.
- A routing fix is checked on both paths, with ten requests each, and then with `istioctl analyze` and the route table again.

## Your missions

You proved the skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Make The Header Route Actually Fire](./labs/lab-01/README.md) | The Route Table Is The Ground Truth | find two causes of a dead header route, leave one owner for the host, and prove both paths |

If you skipped it, go back to it now. It is short.

The section capstone, **Consolidate Three Claimants Into One Route Table**, puts the same skills to work with three owners for one host and two match rules.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. A request with the header <code>testing: true</code> and one without both reach <code>v1</code>. What does that tell you first?</summary>

The failure is total, not partial. The header rule is most likely never checked at all, for example because a catch-all rule sits above it, rather than having a wrong match.
</details>

<details>
<summary>2. What does a rule with no <code>match</code> block compile to?</summary>

A route with a prefix match on `/`. That is true for every HTTP request, so every rule below it can never be reached.
</details>

<details>
<summary>3. Does Envoy pick the most specific matching route?</summary>

No. It walks the list from the top and uses the first route that matches. The order of your `http` list decides.
</details>

<details>
<summary>4. Two <code>VirtualService</code> objects claim <code>notification-service</code> and neither lists a gateway. What does Istio do?</summary>

It merges their routes into one virtual host in an order you do not control. `istioctl analyze` reports `IST0109` as a Warning, because the configuration is valid but its behaviour is undefined.
</details>

<details>
<summary>5. When can two <code>VirtualService</code> objects claim the same host safely?</summary>

When their gateway scopes do not overlap, for example one bound to an ingress `Gateway` and one bound to `mesh`. They then land in different proxies' route tables.
</details>

<details>
<summary>6. Which proxy should you ask with <code>istioctl proxy-config routes</code> when a request is misrouted?</summary>

The client's proxy, the one on the workload that sends the request. The sending proxy makes the routing decision.
</details>

<details>
<summary>7. Why use <code>-o json</code> instead of the table output for a header match problem?</summary>

The table output shows every rule's match as `/*`, which hides header, method and path conditions. The JSON shows the `exact_match` and the cluster each route points at.
</details>

<details>
<summary>8. Why send ten requests and fold them with <code>sort -u</code> to check a fix?</summary>

With two versions behind one Service, one good answer can be luck. Ten requests that fold to one line prove every request went the same way.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-016-playground-020-01
```

If `astrona list` also showed the mission, remove it the same way:

```sh
astrona destroy ats-016-lab-020-01
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with `astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-020/module-01/playground`. It always starts clean, so nothing you broke carries over.

> *One owner per host, the specific rule first, and the route table as the judge: that is how a dead route comes back to life.*
