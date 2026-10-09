# Writing style for this repo

All study text here (course pages, lab docs, READMEs, comments in YAML and
scripts) is for people learning a technical subject, often for a
certification exam. Many of them are not native English speakers and have no
university degree.

## Technical documentation in plain English

This is technical documentation. Say exactly what the system does, with the
real technical terms, in clear and simple English. Never hide a concept
behind a metaphor, a made-up name or a vague word: the reader must learn the
words they will meet in the product, the logs and the exam.

Strict guidelines:

1. Use the correct technical term every time (request, response, pod,
   namespace, Service, sidecar proxy, certificate, mTLS, JWT, listener). The
   first time a term appears in a file, define it in one plain sentence that
   says what it is and what it does. Spell out every acronym on first use.
2. No metaphors or analogies in explanations. Not "the communications
   officer", but "the sidecar proxy (Envoy)"; not "a signal", but "a
   request"; not "the planet", but "the namespace".
3. Simple sentences. Target a Flesch-Kincaid Grade Level of 8 or 9 for the
   prose around the terms. Keep sentences direct; split long sentences into
   two. No corporate buzzwords.
4. Use short paragraphs (max 3-4 sentences per paragraph).
5. Use the active voice ("istiod sends the configuration", not "the
   configuration is sent").

## How this applies to course material

- **Know which file you are in.** A module has a short landing page, a few
  deep-dive parts and a summary page. The landing page is a map: goals, what
  to know first, the order of the parts. The real teaching goes in the parts.
  The summary closes the module. A lab
  has a task, a step-by-step solution and a short intro. Keep each file to its
  job. Do not add "Prerequisite: ... Next: ..." navigation lines to pages;
  the landing page and the course outline already give the order.
- **Keep each part short.** One idea per part, about 5 to 8 minutes of
  reading and at most about 8 command blocks, so a learner can finish it with
  the playground in one sitting of about 15 minutes. Split at a natural seam
  where each half ends with something the learner has seen work. Never split
  only to hit a number. When you split, renumber the files, fix every "Part N"
  reference in the module and `astrona.yaml`.
- **Read like a book, not like a web page.** Each part reads as a chapter of
  a technical book. Open with a short paragraph on the problem it solves and
  why it matters. Link each paragraph to the next with a transition sentence.
  Close with a paragraph that sums up what the reader now knows and the
  question still open, before `## Common pitfalls` and the mission. Write
  explanations as prose; keep bullets for real lists (fields, ordered steps,
  options). Use `##` only when the topic changes and `###` only inside a long
  section, never for a single command. Weave hands-on steps into the text:
  one or two sentences on what to run and why, the command, the real output,
  then a sentence or two on what it shows.
- **The module ends with a summary.** The last page of every module is
  `course-0N-summary.md` with the title `# Summary`: a few short prose
  paragraphs on what the reader learned, organised by idea, optionally with
  one short list of key facts. It names no parts, modules, sections or
  chapters, and has no links, lab table, quiz or commands. Its last line is
  `<!-- astrona:playground:destroy -->` on its own line; the platform turns it
  into the step that removes the playground.
- **Every heading gets an intro.** A `##` section that has `###`
  subsections starts with one to three sentences that say what the section
  is about and why it matters, before the first `###`. Never put a `###`
  directly under a `##`.
- **Every module stands on its own.** Never refer to other sections or
  modules: no "see section 040", "as module 3 showed", "you met this in
  section 000", and no links to pages in another module. If the reader needs
  a fact from elsewhere, state the fact directly in one or two sentences.
  This also goes for parts of the same module: never write "Part 2 shows",
  "from Part 1" or "as in Part 3". Say the fact itself ("the commands below
  need the `scout` `DestinationRule` applied"). This includes the summary.
  The landing page does not have a "Where this fits" section.
- **Write words out in full.** Do not use informal short forms in prose:
  write "communications", "configuration", "repository", "administrator",
  "for example" and "that is", never "comms", "config", "repo", "admin",
  "e.g." or "i.e.". Names in code, commands and file paths stay as they are.
- **Exam terms stay.** The product's own names are what the reader must learn
  (for example a resource kind, a field, a command). Use them as they are and
  define each one in plain technical words the first time it appears in a
  file. Spell out acronyms on first use, with a short plain meaning.
- **The space theme is only for examples.** Space appears in two places and
  nowhere else: the names of the example workloads (the Starfleet: `bridge`,
  `scout`, `shuttle`, `probe`, the `starfleet` and `outpost` namespaces) and
  the short scenario that opens a lab task or a practice exercise (for
  example "the `drifter` in `outpost` must keep reaching the probe"). The
  explanation around an example is plain technical text: write "the
  `shuttle` pod sends a request to the `probe` Service", never "the shuttle
  sends a signal to the probe ship". Do not address the reader as an
  astronaut, and do not use space metaphors (communications officer, mission
  control, badge, airlock, guest list, star chart) for Istio or Kubernetes
  concepts. Titles of pages and labs name the technical task ("Require mTLS
  With PeerAuthentication"), not a space story.
- **Show one real example before the rule.** Start with a concrete case the
  reader can run, then give the general rule.
- **Say which part does the work.** Readers often mix up the parts of a system
  that sit close together. Whenever something happens, say which component
  did it.
- **Never change code to fit the style.** Commands, configuration files, field
  names, resource names, log lines and command output stay exactly as they
  are. They were run and checked on a real system. Never make up command
  output. If you shorten it, say that you did.
- **Prose only.** The grade-level and sentence rules apply to explanations.
  They do not apply to code blocks, tables of field names or reference lists
  (those may stay short and dense).
- **Keep the page furniture the same.** Hands-on steps are part of the prose
  (see "Read like a book"), not boxes or headings of their own. A `> [!TIP]` box is
  only for a real tip: advice the reader can reuse beyond this one step (a
  habit, a shortcut, how to spot a problem, an exam habit). Everything else
  is a normal sentence: notes about the current step ("if the log line is
  old, run it again"), background facts, optional extra steps, and plain
  information. Never a command snippet, never two in a row, and most pages
  need zero or one tip. Each part ends with a
  `## Common pitfalls` `> [!WARNING]` block for that part only. Use a Mermaid
  diagram for a flow, an order or a state change, keep it under about 12
  boxes, and follow it with one sentence that says what it shows.
- **Labs come right after the part they practise.** Do not collect all
  graded labs at the end of a module. In `astrona.yaml`, put each lab (its
  `question.md` reading and the `lab` entry) right after the reading part it
  tests. If a part teaches a gradeable skill and no lab covers it, create a
  new lab. That part then ends with a `## Your mission: <lab title>` section:
  one sentence on what the reader can now do, one on what the mission asks,
  then pause the playground (`astrona stop <playground name>`), the
  `astrona run` and `astrona submit` commands, and finally
  `astrona destroy <lab name>` plus `astrona start <playground name>`.
- **Renew the playground before hands-on work.** Every reading part that
  runs commands has `<!-- astrona:playground:renew -->` exactly once, on its
  own line, right before the first hands-on step (the first "Save this as"
  or the first command block), so the playground timer is reset before the
  learner needs the playground. Not on landing pages (they carry
  `<!-- astrona:playground -->`), summary pages (they carry
  `<!-- astrona:playground:destroy -->`) or pages without commands.
- **Mermaid without HTML.** The platform renders Mermaid with HTML labels
  switched off, so `<br/>` and any other HTML tag break the drawing. Rules:
  - One line per box, no `<br/>`, no HTML. Keep the box to the thing's name
    (`"scout-v2"`, `"istiod"`, `"Service: scout"`).
  - Put the logic on the arrows: `E -->|"version: v2"| P2`,
    `I -->|"CDS"| C`, `A -->|"end-user: jason"| B`. Keep edge labels short.
  - Quote every label. Prefer `flowchart TB`; use `LR` only for a short chain.
  - Sequence diagrams: short participant aliases (`participant S as shuttle`)
    and short message text.
  - Anything longer (cluster names, full hostnames) goes in the sentence under
    the diagram.
- **Every course starts with an Introduction.** It lives in `sections/intro/`
  and is the first entry in `astrona.yaml` (`id: module-intro`, title
  "Introduction"). It has exactly these four pages, in this order:
  - `README.md`, `# Introduction`: what the introduction covers and its three
    pages, named in prose (no links), ending with the topic the course starts
    with.
  - `course-01-welcome.md`, `# Welcome To The Course`: who the course is for,
    the exam domain and what the reader can do at the end, the words the
    course uses, the example app, how the course is laid out and how to read
    a page.
  - `course-02-get-your-machine-ready.md`, `# Get Your Machine Ready`: the
    tools to install, the `astrona` commands used every day, and what to do
    when a start goes wrong.
  - `course-03-how-this-course-is-made.md`, `# How This Course Is Made`: how
    content is written and checked, the maintainers, how to report a mistake,
    and the license.
  The Introduction teaches no product content and has no playground, labs or
  summary. Its only links are the repository's contributors page, issues
  page and license.
- **No links to other course files.** A course page (every reading listed in
  `astrona.yaml`, the playground guide `docs/overview.md`, and a lab's
  `question.md` and `solution.md`) never links to or points the reader at
  another page or file of the repository: no links to parts, summaries,
  labs, `question.md`, other modules, sections or the Introduction, and no
  "see `practice.md`" or "open `config.yaml`". The platform shows the pages in
  the order of `astrona.yaml`, so a link only adds a second, often wrong,
  path. Name a thing in plain words when the reader needs it ("the task is on
  the next page"), and state a fact on the page itself instead of sending the
  reader somewhere else. Repository files for authors (the root `README.md`,
  a lab's or playground's `README.md`) may link.
- **No links to outside sources.** Course pages, labs and playground docs do
  not link to or point at outside websites (the one exception is the
  `resources` field of a lab entry in `astrona.yaml`) (official docs, GitHub, blogs,
  RFCs), and they have no "Reference" or "Official docs" lists. Everything the
  reader needs is explained on the page itself. Not affected: addresses the
  reader actually uses in a command or browser (`http://127.0.0.1:9080`,
  `curl https://httpbin.org`), and the Introduction's contributors and
  "report a mistake" links.
- **Configuration goes to a file first.** Whenever the reader should apply
  YAML (course parts, playground docs, labs), use three separate steps:
  1. "Save this as `virtualservice-scout.yaml`:" followed by a plain
     ` ```yaml ` block with only the YAML. No `cat > file <<'EOF'`, no
     `kubectl apply -f - <<EOF`, no shell around it.
  2. "Apply it:" followed by a ` ```sh ` block with only
     `kubectl apply -f virtualservice-scout.yaml`.
  3. "Then check the result:" followed by the check commands, if any.
  The file name says the kind and the object. If a value must come from the
  reader's cluster (an IP address), use a placeholder like `<PARTNER>` in the
  YAML and say how to get the value (`echo $PARTNER`); never put shell
  variables inside YAML. Apply an object the first time its YAML appears; do
  not show it once "to read" and paste it again later. Never tell the reader
  to apply something from the playground's `examples/` folder: they start the
  playground with `astrona run`, so that folder is not on their machine.
- **Helpers have readable names.** Shell helper functions and variables use
  names that say what they do (`check_route`, `count_versions`,
  `$SERVICE_URL`), never single letters.

## About this repo (ATS016 only)

Everything above is general and can be copied to other course repositories. This
section is only true for this one.

### What the student is trying to learn

- **The goal:** pass the **Troubleshooting** domain of the **Istio Certified
  Associate (ICA)** exam. It is 20% of the exam.
- **What the exam really tests:** finding and fixing a broken mesh by hand,
  on a live cluster, under time pressure, and proving the fix works. So the
  student must *do* things (run `istioctl analyze`, read `proxy-status` and
  `proxy-config`, read an access log line and its response flag, check
  sidecar injection, query a metric), not just recognise words. Every
  explanation should lead to a command they can run, and every fix should be
  proved with a real request that failed before and succeeds after.
- **The three exam topics (curriculum items):** troubleshooting
  configuration, troubleshooting the mesh control plane, and troubleshooting
  the mesh data plane. The README table maps each section to its curriculum
  item.
- **The sections:** the order is the order of an investigation, outside in:
  is the configuration coherent, is the control plane healthy and did it push,
  what does the proxy hold, what did it do to the request, and how much.

  | Section | Title | Curriculum item |
  | --- | --- | --- |
  | 010 | Troubleshooting Configuration With istioctl | Troubleshooting Configuration |
  | 020 | Debugging Conflicting And Shadowed Routes | Troubleshooting Configuration |
  | 030 | Troubleshooting The Mesh Control Plane | Troubleshooting the Mesh Control Plane |
  | 040 | Reading Data Plane Configuration | Troubleshooting the Mesh Data Plane |
  | 050 | Debugging Data Plane Request Failures | Troubleshooting the Mesh Data Plane |
  | 060 | Troubleshooting With Mesh Observability | Troubleshooting Configuration / the Mesh Data Plane |

- **The version:** everything is built and checked on **Istio 1.30.5** on a
  single-node `kind` cluster, installed with
  `istioctl install --set profile=demo -y` (sidecar mode). There is no
  ambient mode in this course. Do not teach fields, flags or output from other
  versions without saying so.
- **The main sources:** the Istio diagnostic tools pages,
  <https://istio.io/latest/docs/ops/diagnostic-tools/>, and the common
  problems pages, <https://istio.io/latest/docs/ops/common-problems/>. Check
  every page against them.

### Terms, not metaphors

Explanations use Istio's, Envoy's and Kubernetes' own words. Define each one
in plain technical language on first use in a file, for example:

| Term | First-use definition (example wording) |
| --- | --- |
| Sidecar proxy (Envoy) | A proxy container Istio adds to each pod; all inbound and outbound traffic of the pod passes through it |
| `istiod` | Istio's control plane; it turns Istio resources into proxy configuration and sends it, plus certificates, to every proxy |
| xDS | The protocol `istiod` uses to push configuration to proxies while they run (LDS, RDS, CDS, EDS for listeners, routes, clusters, endpoints) |
| Sidecar injection | The mutating admission webhook adds the `istio-proxy` container when a pod is created in a namespace or pod that opts in |
| `istioctl analyze` | Checks Istio configuration for problems the API server accepts, for example a reference to a host or subset that does not exist (`IST0101`) |
| `istioctl x describe pod` | Shows which Services, VirtualServices, DestinationRules and policies apply to one pod |
| `istioctl proxy-status` | Shows, per proxy, whether it has the latest configuration from `istiod` (`SYNCED`, `NOT SENT`, `STALE`) |
| `istioctl proxy-config` | Prints the listeners, routes, clusters, endpoints or secrets one proxy actually holds |
| Listener / route / cluster / endpoint | Envoy's configuration objects: where it accepts traffic, how it picks a destination, the upstream group, and the pod IP addresses in that group |
| Access log | One line per request written by Envoy, with the response code and the response flag |
| Response flag | A short Envoy code in the access log that says why a request failed (`UF` upstream connection failure, `UH` no healthy upstream, `NR` no route, `UT` upstream timeout) |
| Shadowed route | A route rule that can never match because an earlier rule in the same route table matches first |
| Kiali | The Istio service graph console; it draws traffic and flags configuration problems from Prometheus data and the cluster |
| Prometheus / Grafana | Prometheus stores the metrics the proxies emit (`istio_requests_total`); Grafana draws dashboards from them |

Older pages still use space metaphors and mission language ("Wrap-Up:
Mission Debrief", "mission control"). Replace them with the real terms when
you touch a page.

### The example workloads

Every section uses the same small app, deployed into its own namespace per
module (`analyze-demo`, `describe-demo`, `conflict-demo`, `cphealth-demo`,
`proxysync-demo`, `noinject-demo`, `proxycfg-demo`, `fivezerothree-demo`,
`accesslog-demo`, `mtlsfail-demo`, `kiali-demo`, `metrics-demo`; capstones
use `*capstone-demo` namespaces). The Kubernetes names are plain service
names, so describe them in technical terms and use them as they are.

| Kubernetes name | Image | What it is |
| --- | --- | --- |
| `notification-service` (Service) | | Service on port `80` (`http`), target port `8084` |
| `notification-service-v1` / `-v2` | `nginx:1.27-alpine` | Backend Deployments, labels `app: notification-service` and `version: v1` / `v2`; nginx returns a fixed JSON body from a ConfigMap |
| `tester` | `curlimages/curl` | Client pod in the mesh; every test request is sent from here with `kubectl exec deploy/tester -- curl ...` |
| `reporting-service` | `mccutchen/go-httpbin:v2.15.0` | HTTP echo server on port `8080`, used where a second backend is needed (sidecar injection module and its capstone) |
| `billing-service` (in `cpcapstone-legacy`) | | Workload in a namespace without sidecar injection, used in the control plane capstone |

The workloads use the `default` service account. The space-named Starfleet
app (`bridge`, `scout`, `shuttle`, `probe`) from the general rules above is
not deployed in this repository yet; do not refer to it in a page until a
playground actually runs it.

### Environment facts the text must respect

- **Playgrounds and labs install Istio with `istioctl`**, pinned to 1.30.5
  in each `prepare.sh` or `bootstrap/01-install-istio.sh`, with the `demo`
  profile. The `demo` profile includes the ingress and egress gateways and
  turns on Envoy access logs to stdout.
- **Section 060 installs addons.** Prometheus, Kiali and Grafana come from
  `https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons`,
  so those environments need outbound internet and take longer to start.
  Pages reach them with `kubectl -n istio-system port-forward svc/kiali 20001:20001`,
  `svc/grafana 3000:3000` and `svc/prometheus 9090:9090`.
- **Many environments start broken on purpose.** A playground or lab often
  applies a `broken-config.yaml` (or similar) next to `lab-start.yaml`. The
  fault is the material. Never "fix" it in the bootstrap.
- **No load balancer on `kind`.** A gateway Service's `EXTERNAL-IP` stays
  `<pending>`; use `kubectl port-forward` when a page needs the gateway.
- **Istio 1.30.5 output that older pages got wrong.** Check these before you
  copy output from memory or from an older page:
  - `istioctl analyze` names objects as `<Kind> <namespace>/<name>`, prints
    one message per object involved (`IST0109` appears once on each
    `VirtualService`), and exits with code `79` when it finds issues.
  - Severities: `IST0101` Error, `IST0102` Info, `IST0103` Warning,
    `IST0106` Error (schema), `IST0109` Error, `IST0130` Warning
    (unreachable rule), `IST0002` Warning (deprecated).
  - A shadowed route rule is not silent: `kubectl apply` prints
    `Warning: virtualService rule #N not used`, and analyze reports `IST0130`.
  - Plain `istioctl proxy-status` shows `NAME CLUSTER ISTIOD VERSION
    SUBSCRIBED TYPES`; the per-type `SYNCED`/`STALE` columns need `-v 1`. A
    rejected push shows as `ERROR`.
  - Route JSON from `proxy-config routes -o json` holds header matches as
    `headers[].stringMatch.exact`; there is no `exact_match` field.
  - The default Envoy log level of every scope is `warning`.
- **The proof is a request from `tester`.** A fix is proven with
  `kubectl exec` from the `tester` pod to `http://notification-service`, plus
  the matching diagnostic command (`istioctl analyze` clean,
  `proxy-status` `SYNCED`, the route or cluster present in `proxy-config`, a
  `200` in the access log).

### Where things are in this repo

| What | Where |
| --- | --- |
| Course outline the platform reads: every reading page and lab, in order. Never list `solution.md` here | `astrona.yaml` |
| Overview, sections and modules tables, the investigation order, how to run things | `README.md` |
| Introduction (see "Every course starts with an Introduction") | `sections/intro/` |
| Section overview and its modules | `sections/section-0N0/README.md` |
| Module reading: landing page, deep-dive parts, closing page | `sections/section-0N0/module-0M/course.md`, `course-0N-*.md` |
| Graded lab: task, walkthrough, setup, grader | `.../labs/lab-01/` (`question.md`, `solution.md`, `prerequisites.md`, `bootstrap/`, `manifests/`, `solution/`, `testing/`, `validation/`) |
| Ungraded sandbox for a module | `.../playground/` (`config.yaml`, `bootstrap/prepare.sh`, `manifests/`, `docs/overview.md`, which is the only learner page) |
| One graded integration lab per section | `sections/section-0N0/capstone/labs/lab-01/` |

A lab folder holds:

| Path | Purpose |
| --- | --- |
| `config.yaml` | Lab definition; `metadata.docs` points at `question.md` and `solution.md` |
| `README.md` | Short intro for authors with `estimated_duration` front matter and the run, submit and destroy commands |
| `prerequisites.md` | What the learner needs before starting |
| `question.md` | The exam-style task. Starts with `# Question` and `Solve this question on: \`terminal\`` |
| `solution.md` | Step-by-step walkthrough with real output |
| `bootstrap/01-install-istio.sh`, `02-seed-workloads.sh` | Istio install and the broken starting state |
| `manifests/` | `lab-start.yaml` (workloads) and the faulty configuration the learner must fix |
| `solution/apply.sh`, `solution/solution.yaml` | Reference end state, applied only by `astrona test` |
| `testing/` | Helpers `astrona test` runs (for example `wait-for-istiod.sh`) |
| `validation/validate-*.sh` | Behavioural grading, one script per check (for example `validate-analyze-clean.sh`, `validate-traffic-restored.sh`) |

### Lab metadata in `astrona.yaml`

`astrona.yaml` has a `training:` block (id `ATS016`, domain
`Troubleshooting`, weight `20`) and one entry per section under `modules:`
(`module-010`, `module-020` and so on). Each section's `content` lists, in
order: the section `README.md`, then for each module its landing page, its
parts, and right after the part a lab tests, a `Question` reading
(`labs/lab-01/question.md`) followed by the `type: lab` entry; the module's
closing page comes last. The section capstone closes the section.
Playgrounds are not listed: the landing page's `<!-- astrona:playground -->`
marker shows them.

Every `type: lab` entry (module labs and capstones) carries these fields, in
this order:

```yaml
      - type: reading
        title: Question
        path: sections/section-010/module-01/labs/lab-01/question.md
      - type: lab
        title: "Find And Fix The Configuration Errors Lab"
        path: sections/section-010/module-01/labs/lab-01
        difficulty: beginner
        estimated_duration: 15m
        topic: configuration
        task_kind: troubleshooting
        tags: [istioctl-analyze, ist0101, virtualservice, destinationrule, subsets, gateway]
        learning_goals:
          - Find every reference that does not resolve with istioctl analyze
          - Fix the VirtualService so it routes only to subsets and gateways that exist
          - Prove the fix with a clean analyze run and a 200 from the tester pod
        resources:
          - name: "Diagnose your configuration with istioctl analyze"
            url: https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-analyze/
```

- `difficulty`: `beginner`, `intermediate` or `advanced`.
- `estimated_duration`: realistic time to solve it, for example `15m`, `30m`, `45m`.
- `topic`: exactly one of `configuration`, `routing`, `control-plane`,
  `injection`, `data-plane`, `request-failures`, `security`,
  `observability`.
- `task_kind`: exactly one of `build` (write the configuration from
  scratch), `troubleshooting` (find and fix what is broken) or `migration`
  (move a working setup to another mode or layout). Almost every lab here is
  `troubleshooting`. The platform filters labs by it, so it is a field of its
  own, never a tag.
- `tags`: 4 to 8 ids, only from the tag list below. Add a new tag to the list
  first if nothing fits.
- `learning_goals`: 2 or 3 plain sentences, each starting with a verb, saying
  what the learner proves in this lab.
- `resources`: 1 to 4 documentation pages, each with a `name` and a `url`
  that loads. This is the **only** place outside links are allowed: the
  platform shows them as optional further reading next to the lab.

**Tag list** (lower case, hyphens, never synonyms):

- Istio objects: `virtualservice`, `destinationrule`, `gateway`,
  `peerauthentication`, `authorizationpolicy`, `telemetry`, `subsets`,
  `service-ports`, `protocol-selection`
- Configuration: `istioctl-analyze`, `ist0101`, `istioctl-x-describe`,
  `validating-webhook`, `host-conflict`, `shadowed-route`, `rule-order`,
  `header-matching`, `uri-matching`, `fault-injection`, `timeouts`
- Control plane: `istiod-health`, `istiod-logs`, `proxy-status`, `xds`,
  `revisions`, `sidecar-injection`, `injection-opt-out`
- Data plane: `proxy-config`, `routes`, `clusters`, `endpoints`,
  `envoy-log-level`, `network-policy`, `mtls-strict`, `mtls-mismatch`
- Failure signatures: `503-uf`, `503-nc`, `504-ut`, `rbac-403`,
  `response-flags`
- Observability: `access-log`, `istio-metrics`, `prometheus`, `promql`,
  `grafana`, `kiali`, `reporter-label`
- Tools: `bug-report`

### Running things

```bash
# Playground (ungraded)
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-01/playground
astrona destroy ats-016-playground-010-01   # takes metadata.name from config.yaml, not the path

# Lab or capstone (graded against the live cluster)
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-010/module-01/labs/lab-01
astrona submit -c sections/section-010/module-01/labs/lab-01
astrona destroy ats-016-lab-010-01

# Authors: run a local, uncommitted copy, and prove a lab passes with its reference solution
astrona run -c sections/section-010/module-01/playground
astrona test -c sections/section-010/module-01/labs/lab-01
```

Names: a playground is `ats-016-playground-<section>-<module>`, a module lab
is `ats-016-lab-<section>-<module>` and a capstone is
`ats-016-capstone-<section>`; keep those names. A second lab in a module
takes `ats-016-lab-<section>-<module>-<lab>`, for example
`ats-016-lab-040-02-02`, so two labs never share a name. Lab bootstrap
scripts do not pin a kube context: astrona sets `KUBECONFIG` for the lab, and
`astrona test` runs on a cluster with a different name. Every lab must pass
`astrona validate` and `astrona test`.

Graders check **behaviour**, not just that an object exists: send real
traffic from `tester` and check that the broken request now succeeds. Many
graders also reject the plausible but wrong fix (inventing a missing subset,
relaxing mTLS to `PERMISSIVE` to hide an error, deleting a policy instead of
correcting it). A lab's `question.md` and `solution.md` must match what its
`validation/` scripts actually check.

Test clusters on the maintainer's machine: one at a time. Podman has 10 GiB
and also runs the platform stack; parallel clusters run it out of memory.
The section 060 addons make those clusters the heaviest. Never touch clusters
you did not create (for example `istio-doc`).

### Where to find trusted sources

Check facts here before writing them down. Prefer these over memory.

- **Diagnostic tools (the course spine):**
  [istioctl analyze](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-analyze/),
  [istioctl describe](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-describe/),
  [proxy-config and proxy-status](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/),
  [component logging](https://istio.io/latest/docs/ops/diagnostic-tools/component-logging/),
  [analysis messages](https://istio.io/latest/docs/reference/config/analysis/)
- **Common problems:**
  [network](https://istio.io/latest/docs/ops/common-problems/network-issues/),
  [security](https://istio.io/latest/docs/ops/common-problems/security-issues/),
  [sidecar injection](https://istio.io/latest/docs/ops/common-problems/injection/),
  [configuration validation](https://istio.io/latest/docs/ops/common-problems/validation/),
  [protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/),
  [application requirements](https://istio.io/latest/docs/ops/deployment/application-requirements/)
- **API reference:**
  [VirtualService](https://istio.io/latest/docs/reference/config/networking/virtual-service/),
  [DestinationRule](https://istio.io/latest/docs/reference/config/networking/destination-rule/),
  [PeerAuthentication](https://istio.io/latest/docs/reference/config/security/peer_authentication/),
  [AuthorizationPolicy](https://istio.io/latest/docs/reference/config/security/authorization-policy/),
  [Telemetry](https://istio.io/latest/docs/reference/config/telemetry/),
  [standard metrics](https://istio.io/latest/docs/reference/config/metrics/)
- **Observability:**
  [Envoy access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/),
  [Envoy access log format and response flags](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage),
  [querying metrics](https://istio.io/latest/docs/tasks/observability/metrics/querying-metrics/),
  [Prometheus](https://istio.io/latest/docs/ops/integrations/prometheus/),
  [Grafana](https://istio.io/latest/docs/ops/integrations/grafana/),
  [Kiali](https://istio.io/latest/docs/ops/integrations/kiali/)
- **The exam itself:** the ICA page on the Linux Foundation / CNCF training
  site lists the official curriculum. The domain weight (20%) and topic list
  above come from this repository's README and `astrona.yaml` and have not
  been re-checked against it.

### Skills to use here

The `astrona-course-*` skills do most authoring jobs in this repository: planning
(`domain-plan`), creating the tree (`domain-scaffold`), building modules
(`domain-build`), deep-dive parts (`deep-dive`), labs and playgrounds (`lab`),
lab docs (`lab-docs`), challenges (`create-challenge`), quizzes
(`generate-assessment`) and fact-checking (`review-accuracy`).
