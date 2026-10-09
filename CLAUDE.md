# Writing style for this repo

All study text here (course pages, lab docs, READMEs, comments in YAML and
scripts) is for people learning a technical subject, often for a
certification exam. Many of them are not native English speakers and have no
university degree.

## Plain English

Write the text in Plain English for a general adult audience (18+) without a
university degree. The content must be highly accessible and easy to
understand for non-technical readers, without feeling childish.

Strict guidelines:

1. Target a Flesch-Kincaid Grade Level of 8 or 9 (equivalent to a standard
   newspaper article).
2. Avoid all technical jargon, acronyms, and corporate buzzwords. If a
   technical term is necessary, explain it immediately using an everyday
   analogy.
3. Keep sentences conversational and direct. Split long sentences into two.
4. Use short paragraphs (max 3-4 sentences per paragraph) and clear
   subheadings to make the text scannable.
5. Use the active voice (e.g., "We did this" instead of "This was done by us").

## How this applies to course material

- **Know which file you are in.** A module has a short landing page and a few
  deep-dive parts. The landing page is a map: goals, what to know first, the
  order of the parts, where it fits. The real teaching goes in the parts. A lab
  has a task, a step-by-step solution and a short intro. Keep each file to its
  job. Do not add "Prerequisite: ... Next: ..." navigation lines to pages;
  the landing page and the course outline already give the order.
- **Keep each part short.** One idea per part, about 5 to 8 minutes of
  reading and at most about 8 command blocks, so a learner can finish it with
  the playground in one sitting of about 15 minutes. Split at a natural seam
  where each half ends with something the learner has seen work. Never split
  only to hit a number. When you split, renumber the files, fix every "Part N"
  reference in the module, the wrap-up links and `astrona.yaml`.
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
  need the `notification` `DestinationRule` applied"). The wrap-up page is the one
  exception: it recaps each part and links to it.
  The landing page does not have a "Where this fits" section.
- **Write words out in full.** Do not use informal short forms in prose:
  write "communications", "configuration", "repository", "administrator",
  "for example" and "that is", never "comms", "config", "repo", "admin",
  "e.g." or "i.e.". Names in code, commands and file paths stay as they are.
- **Exam terms stay.** The product's own names are what the reader must learn
  (for example a resource kind, a field, a command). Keep them, but explain
  each one in plain words, with an everyday analogy, the first time it appears
  in a file. Spell out acronyms on first use, with a short plain meaning.
- **Analogies come from space, and the reader is an astronaut.** When a term
  needs an everyday picture, use space: spaceships, planets, solar systems,
  space stations, mission control, signals, docking, star charts, airlocks,
  even the Death Star. Talk to the reader as an astronaut (for example "your
  first mission", "astronaut, check your flight log"), but not in every
  sentence. Requests are **signals** that ships send to each other. Use one
  analogy per hard idea, keep it short, and keep it the same everywhere (if
  the repository has an analogy glossary, use it). The analogy helps the reader; it
  never replaces the real term, and it never changes code or output.
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
- **Keep the page furniture the same.** Hands-on steps are normal page
  content, not boxes: a short `###` subsection (for example "See it in your
  playground") with one sentence saying what to do, the command, the real
  output, and one or two sentences saying what it shows. A `> [!TIP]` box is
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
  `astrona destroy <lab name>` plus `astrona start <playground name>`. The
  wrap-up lists the missions and ends with cleaning up the playground
  (`astrona list`, `astrona destroy <playground name>`).
- **Renew the playground before hands-on work.** Every reading part that
  runs commands has `<!-- astrona:playground:renew -->` exactly once, on its
  own line, right before the first hands-on step (the first "Save this as"
  or the first command block), so the playground timer is reset before the
  learner needs the playground. Not on landing pages (they carry
  `<!-- astrona:playground -->`), wrap-up pages or pages without commands.
- **Mermaid without HTML.** The platform renders Mermaid with HTML labels
  switched off, so `<br/>` and any other HTML tag break the drawing. Rules:
  - One line per box, no `<br/>`, no HTML. Keep the box to the thing's name
    (`"notification-service-v2"`, `"istiod"`, `"Service: notification-service"`).
  - Put the logic on the arrows: `E -->|"version: v2"| P2`,
    `I -->|"CDS"| C`, `A -->|"testing: true"| B`. Keep edge labels short.
  - Quote every label. Prefer `flowchart TB`; use `LR` only for a short chain.
  - Sequence diagrams: short participant aliases (`participant T as tester`)
    and short message text.
  - Anything longer (cluster names, full hostnames) goes in the sentence under
    the diagram.
- **No links to outside sources.** Course pages, labs and playground docs do
  not link to or point at outside websites (the one exception is the
  `resources` field of a lab entry in `astrona.yaml`) (official docs, GitHub, blogs,
  RFCs), and they have no "Reference" or "Official docs" lists. Everything the
  reader needs is explained on the page itself. Not affected: addresses the
  reader actually uses in a command or browser (`http://127.0.0.1:9080`,
  `curl https://httpbin.org`), and the Mission Briefing's contributors and
  "report a mistake" links.
- **Configuration goes to a file first.** Whenever the reader should apply
  YAML (course parts, playground docs, labs), use three separate steps:
  1. "Save this as `virtualservice-notification.yaml`:" followed by a plain
     ` ```yaml ` block with only the YAML. No `cat > file <<'EOF'`, no
     `kubectl apply -f - <<EOF`, no shell around it.
  2. "Apply it:" followed by a ` ```sh ` block with only
     `kubectl apply -f virtualservice-notification.yaml`.
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
- **What the exam really tests:** finding and fixing what is broken in a live
  mesh, by hand, under time pressure, and proving the fix works. So the
  student must *do* things (run `istioctl analyze`, read `proxy-status` and
  `proxy-config`, read an access log line and its response flag, fix the one
  object that is wrong), not just recognise words. Every explanation should
  lead to something they can run, and every fix should be proved twice: once
  with the tool that found the fault, once with a real request.
- **The three exam topics (curriculum items):** troubleshooting
  configuration, troubleshooting the mesh control plane, and troubleshooting
  the mesh data plane. The course follows the order of an investigation,
  outside in: is the configuration coherent, did it reach the proxy, is there
  a proxy at all, what is the proxy doing, what did it do to this request, and
  how much and since when.
- **The sections:**

  | Section | Title | Exam topic |
  | --- | --- | --- |
  | 010 | Troubleshooting Configuration With istioctl | Troubleshooting Configuration |
  | 020 | Debugging Conflicting And Shadowed Routes | Troubleshooting Configuration |
  | 030 | Troubleshooting The Mesh Control Plane | Troubleshooting the Mesh Control Plane |
  | 040 | Reading Data Plane Configuration | Troubleshooting the Mesh Data Plane |
  | 050 | Debugging Data Plane Request Failures | Troubleshooting the Mesh Data Plane |
  | 060 | Troubleshooting With Mesh Observability | Troubleshooting Configuration / the Mesh Data Plane |

- **The version:** everything is built and checked on **Istio 1.30.5** on a
  single-node `kind` cluster, installed with
  `istioctl install --set profile=demo -y`. Do not teach fields or behaviour
  from other versions without saying so.
- **The main sources:** the Istio diagnostic tools pages,
  <https://istio.io/latest/docs/ops/diagnostic-tools/>, and the common
  problems pages, <https://istio.io/latest/docs/ops/common-problems/>. Check
  every page against them and the API reference.

### Space analogy glossary

Use these pictures for these terms, in every course page, lab and playground.
Keep them consistent so the astronaut builds one picture of the universe. This
is the same universe as the other Istio courses (ATS014, ATS015): the first
two tables are shared with them, the rest is for troubleshooting. Most pages
written before these rules have no space analogies yet; add them when you
rework a page, using this table.

**The universe**

| Term | Space picture |
| --- | --- |
| The learner | An astronaut (a cadet on their first missions) |
| Kubernetes cluster | A solar system |
| Namespace | A planet in that solar system |
| Pod | A spaceship |
| Container | A module inside the ship (the app is the crew) |
| Kubernetes Service | A beacon: one call sign that a whole group of ships answers to |
| Service account | The ship's registration papers |
| Request / response | A signal sent out, and the reply signal |
| Port | A radio channel |
| Service mesh | The fleet's shared signal network |
| `kind` cluster on your laptop | A training solar system in the simulator |
| Kubernetes API server | The registry office: every object must be filed there |
| etcd | The registry office's archive |

**The mesh**

| Term | Space picture |
| --- | --- |
| Sidecar proxy (Envoy) | The ship's communications officer: every signal in or out goes through them |
| Sidecar injection | Putting a communications officer on board when the ship launches (ships already flying do not get one) |
| Injection webhook | The launch-pad crew that puts the communications officer on board, if the planet's and the ship's own orders allow it |
| `sidecar.istio.io/inject: "false"` | The ship's own orders: "no officer on board", which beat the planet's rule |
| Revision (`istio.io/rev`) | A named shift at mission control; a planet tied to a shift that does not exist gets no officers |
| `istiod` (control plane) | Mission control: it sends every communications officer their orders and issues ID badges |
| xDS push | Mission control radioing new orders to every ship in flight, no landing needed (no restart) |
| ACK / NACK | The officer radioing back "orders received" / "orders rejected, keeping the old ones" |
| mTLS | A secret handshake: both ships show their badges before they talk |
| `PeerAuthentication` `STRICT` | The airlock rule: no handshake, no docking |
| `DestinationRule` `tls.mode` | How the sending ship approaches the airlock: with the handshake, or without (`DISABLE`) |
| `AuthorizationPolicy` | The guard's list at the airlock: who may come aboard and what they may do |
| `RBAC: access denied` (403) | The guard turned the signal away at the airlock |

**Steering signals**

| Term | Space picture |
| --- | --- |
| `VirtualService` | The flight plan: which way a signal flies, based on what it carries |
| Route rules, read top to bottom | The flight plan's checklist; the first line that fits is used |
| Shadowed rule | A checklist line that can never be reached, because a line above it catches every signal first |
| Two objects claiming one host | Two flight plans for one beacon; only one is followed and nobody tells you which |
| `DestinationRule` subset (v1, v2) | Ship classes of the same model: same call sign, different build |
| Missing subset | A flight plan that names a ship class nobody built |
| Fault injection | A training drill: mission control makes signals fail on purpose |
| Timeout / circuit breaker | Giving up on a late reply / closing the docking bay when too many ships queue |

**Investigation tools**

| Term | Space picture |
| --- | --- |
| Validating webhook | The registry clerk: checks each form on its own, never against the other forms |
| `istioctl analyze` | The pre-flight inspector: reads every form together and finds the ones that point at nothing |
| `IST0101` and other analyzer codes | The inspector's warning codes on the inspection report |
| `istioctl x describe pod` | The ship's dossier: every rule that touches one ship, on one page |
| `istioctl bug-report` | The black box: one archive of the whole solar system's state, to hand to someone else |
| Envoy log level (`debug`) | Asking the communications officer to think out loud for a moment, then go quiet again |
| `istioctl proxy-status` | Mission control's roll call: which ships answer, and whether they hold the latest orders |
| `istioctl proxy-config` | Reading the orders book on one ship |
| Listener / route / cluster / endpoint | The radio channel the officer listens on / the flight plan table / a destination squadron / one ship's actual address |
| Access log | The ship's flight log: one line per signal |
| Response flag (`UH`, `UF`, `UT`, `NR`, ...) | The short code the officer stamps on a failed signal in the flight log |
| `Telemetry` resource | The flight log settings: which planets keep a log, and what goes in it |
| Prometheus and its metrics | The telemetry recorder: counts every signal, by sender, receiver and reply code |
| `reporter` label | Which ship filed the report: the sender (`source`) or the receiver (`destination`) |
| Grafana | The dashboard screens in mission control |
| Kiali | The tactical map: every ship and every signal path on one screen, with red where it hurts |

### The sample apps the playgrounds and labs use

This course does **not** run the Starfleet (the Bookinfo sample with space
names). Every playground and lab runs its own small app, in its own planet
(namespace), and the resource names in code stay exactly as they are. Use the
space pictures in prose (for example "the `tester` ship sends a signal to the
`notification-service` beacon"), never as new names.

| Kubernetes name | What it is | Space picture in prose |
| --- | --- | --- |
| `notification-service` (Service, port `80`) | The beacon in front of the app | The beacon most signals are aimed at |
| `notification-service-v1`, `notification-service-v2` (Deployments, `nginx:1.27-alpine`, labels `version: v1` / `v2`) | The app, in one or two versions; v2 answers differently so you can tell them apart | Two ship classes of one model |
| `tester` (Deployment, `curlimages/curl`) | The client every test request is sent from | Your test ship |
| `reporting-service` | A second app (`mccutchen/go-httpbin` in section 030, `nginx` in the section 040 capstone) | A second beacon |
| `orders-service`, `payments-service`, `billing-service` | The three workloads of the section 030 capstone | Three ships, three different faults |

Each module has its own namespace: `analyze-demo`, `describe-demo`,
`conflict-demo`, `cphealth-demo`, `proxysync-demo`, `noinject-demo`,
`proxycfg-demo`, `fivezerothree-demo`, `accesslog-demo`, `mtlsfail-demo`,
`kiali-demo` and `metrics-demo`. The capstones use `audit-demo`,
`routing-demo`, `cpcapstone-demo` (plus `cpcapstone-legacy`, where
`billing-service` runs), `dpcapstone-demo`, `logcapstone-demo` and
`obscapstone-demo`. The app's answers come from its nginx configuration
(`notification-service-v1-nginx-conf`, container port `8084`, Service port
`80`): v1 answers `["EMAIL"]` on any path, so requests such as
`POST /notify` are just a path the tester chooses. Never change them.

### Environment facts the text must respect

- **Istio is installed with `istioctl`,** not Helm:
  `istioctl install --set profile=demo -y`, with `istioctl` 1.30.5 pinned by
  the bootstrap script (`playground/bootstrap/prepare.sh`,
  `labs/lab-01/bootstrap/01-install-istio.sh`). The `demo` profile turns
  access logging on for the whole mesh.
- **Many playgrounds start broken on purpose.** Their
  `playground/manifests/broken-config.yaml` (or `policies.yaml`,
  `fault.yaml`) is applied after the workloads. That is the material, not a
  defect. Course pages tell the reader to diagnose it before reading the
  file.
- **Section 060 installs addons.** Prometheus, Kiali and Grafana come from
  `https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons`;
  the Kiali module installs Prometheus and Kiali, the metrics module
  Prometheus and Grafana, the capstone all three. They take longer to start.
  There are no `portForwards` in `config.yaml`: the reader opens the
  dashboards with `istioctl dashboard` or `kubectl port-forward`.
- **No load balancer on `kind`** and no ingress gateway in use: every test
  request is sent from the `tester` pod with `kubectl exec ... curl`.
- **Graders check behaviour and state.** Validation scripts send real
  requests from `tester`, read `istioctl proxy-status`, `proxy-config`,
  access logs and Prometheus, and several of them reject the
  plausible-but-wrong fix (inventing a missing subset, relaxing mTLS,
  deleting a policy instead of correcting it).

### Where things are in this repo

| What | Where |
| --- | --- |
| Course outline the platform reads: every reading page and lab, in order. Never list `solution.md` here | `astrona.yaml` |
| Overview, sections table, the investigation method, how to run things | `README.md` |
| Section overview and its modules | `sections/section-0N0/README.md` |
| Module reading: landing page, deep-dive parts, wrap-up | `sections/section-0N0/module-0M/course.md`, `course-0N-*.md` |
| Graded lab: task, walkthrough, setup, grader | `.../labs/lab-0N/` (`question.md`, `solution.md`, `prerequisites.md`, `bootstrap/`, `manifests/`, `solution/apply.sh`, `validation/`, `testing/`) |
| Ungraded sandbox for a module | `.../playground/` (`config.yaml`, `bootstrap/prepare.sh`, `manifests/`, `docs/overview.md` says what is in the box) |
| One graded integration lab per section | `sections/section-0N0/capstone/labs/lab-01/` |

A lab folder holds:

| Path | Purpose |
| --- | --- |
| `config.yaml` | Lab definition; `metadata.docs` has `question: "question.md"` and `solution: "solution.md"` |
| `README.md` | Short intro and the run, submit and destroy commands |
| `question.md` | The exam-style task. Starts with `# Question` and `Solve this question on: \`terminal\`` |
| `solution.md` | Step-by-step walkthrough with real output |
| `prerequisites.md` | What the learner should know before starting |
| `bootstrap/01-install-istio.sh`, `bootstrap/02-seed-workloads.sh`, `manifests/` | Istio install and the broken starting state, never the fix |
| `testing/wait-for-istiod.sh` | Waits for the validating webhook before `astrona test` applies the fix |
| `solution/apply.sh`, `solution/solution.yaml` | Reference end state, applied only by `astrona test` |
| `validation/validate-*.sh` | Grading: one script per check |

### Lab metadata in `astrona.yaml`

`astrona.yaml` has one entry per section under `modules:` (`module-010`,
`module-020` and so on). Each section's `content` lists, in order: the
section `README.md`, then for each module its landing page, its parts, and
right after the part a lab tests, a `Question` reading
(`labs/lab-0N/question.md`) followed by the `type: lab` entry; the module's
wrap-up page comes last. The section capstone closes the section. Playgrounds
are not listed: the landing page's `<!-- astrona:playground -->` marker shows
them.

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
        estimated_duration: 20m
        topic: configuration
        task_kind: troubleshooting
        tags: [istioctl-analyze, ist0101, virtualservice, destinationrule, subsets]
        learning_goals:
          - Find every reference that does not resolve with istioctl analyze
          - Fix the VirtualService so it routes only to subsets that exist
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
  (move a working setup to another mode or layout). The platform filters labs
  by it, so it is a field of its own, never a tag.
- `tags`: 4 to 8 ids, only from the tag list below. Add a new tag to the list
  first if nothing fits.
- `learning_goals`: 2 or 3 plain sentences, each starting with a verb, saying
  what the learner proves in this lab.
- `resources`: 1 to 4 documentation pages, each with a `name` and a `url`
  that loads. This is the **only** place outside links are allowed: the
  platform shows them as optional further reading next to the lab.

**Tag list** (lower case, hyphens, never synonyms):

- Istio and Kubernetes objects: `virtualservice`, `destinationrule`,
  `peerauthentication`, `authorizationpolicy`, `telemetry`, `gateway`,
  `network-policy`, `service-ports`
- Configuration analysis: `istioctl-analyze`, `istioctl-validate`,
  `istioctl-x-describe`, `bug-report`, `envoy-log-level`,
  `validating-webhook`, `ist0101`, `ist0102`, `ist0103`
- Routing: `rule-order`, `shadowed-route`, `host-conflict`,
  `header-matching`, `uri-matching`, `subsets`, `catch-all`
- Control plane: `istiod-health`, `istiod-logs`, `istiod-metrics`, `xds`,
  `nack`, `revisions`, `sidecar-injection`, `injection-opt-out`
- Data plane configuration: `proxy-config`, `proxy-status`, `listeners`,
  `routes`, `clusters`, `endpoints`, `protocol-selection`
- Request failures: `access-log`, `response-flags`, `timeouts`,
  `circuit-breaking`, `fault-injection`, `mtls-strict`, `mtls-mismatch`,
  `503-uh`, `503-uf`, `503-nc`, `504-ut`, `404-nr`, `rbac-403`
- Observability: `kiali`, `prometheus`, `grafana`, `promql`,
  `istio-metrics`, `reporter-label`

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
`ats-016-lab-<section>-<module>`, and a capstone `ats-016-capstone-<section>`
(for example `ats-016-capstone-030`). Keep those names. A new lab takes
`ats-016-lab-<section>-<module>-<lab>`, for example `ats-016-lab-040-01-02`,
so two labs never share a name. Lab bootstrap scripts do not pin a kube
context: astrona sets `KUBECONFIG` for the lab, and `astrona test` runs on a
cluster with a different name. Every lab must pass `astrona validate` and
`astrona test`.

A lab's `question.md` and `solution.md` must match what its `validation/`
scripts actually check.

Test clusters on the maintainer's machine: one at a time. Podman has 10 GiB
and also runs the platform stack; parallel clusters run it out of memory.
Never touch clusters you did not create.

### Where to find trusted sources

Check facts here before writing them down. Prefer these over memory.

- **Diagnostic tools (the course spine):**
  <https://istio.io/latest/docs/ops/diagnostic-tools/>, especially
  [istioctl analyze](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-analyze/),
  [proxy-status and proxy-config](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/),
  [istioctl describe](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-describe/),
  [bug-report](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl/)
  and [component logging](https://istio.io/latest/docs/ops/diagnostic-tools/component-logging/)
- **Analyzer messages:** <https://istio.io/latest/docs/reference/config/analysis/>
- **Common problems:**
  [traffic management](https://istio.io/latest/docs/ops/common-problems/network-issues/),
  [security](https://istio.io/latest/docs/ops/common-problems/security-issues/),
  [sidecar injection](https://istio.io/latest/docs/ops/common-problems/injection/),
  [configuration validation](https://istio.io/latest/docs/ops/common-problems/validation/)
- **Access logs and telemetry:**
  [Envoy access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/),
  [Telemetry API](https://istio.io/latest/docs/reference/config/telemetry/),
  [Istio standard metrics](https://istio.io/latest/docs/reference/config/metrics/),
  and the Envoy access log page for response flags:
  <https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage>
- **Observability addons:**
  [Kiali](https://istio.io/latest/docs/ops/integrations/kiali/),
  [Prometheus](https://istio.io/latest/docs/ops/integrations/prometheus/),
  [Grafana](https://istio.io/latest/docs/ops/integrations/grafana/)
- **API reference, one page per object:**
  [VirtualService](https://istio.io/latest/docs/reference/config/networking/virtual-service/),
  [DestinationRule](https://istio.io/latest/docs/reference/config/networking/destination-rule/),
  [PeerAuthentication](https://istio.io/latest/docs/reference/config/security/peer_authentication/),
  [AuthorizationPolicy](https://istio.io/latest/docs/reference/config/security/authorization-policy/)
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
