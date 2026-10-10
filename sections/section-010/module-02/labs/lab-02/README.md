---
estimated_duration: 15m
---

# Capture A Limited bug-report Archive

- **ID:** LAB
- **Slug:** ats-016-lab-010-02-02
- **Author:** Paris Nakita Kejser
- **Type:** Astrona graded lab

Graded lab for the namespaces `describe-demo` and `noise-demo`. The learner captures an `istioctl bug-report` archive that holds exactly one workload's proxy plus `istiod`, written to `/tmp/ats-016-bug-report/bug-report.tar.gz`. Read `question.md` for the task; `solution.md` is the walkthrough.

## Run it

```sh
astrona run -c .
astrona submit
astrona destroy ats-016-lab-010-02-02
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-016-lab-010-02-02`), not
the config path.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition, bootstrap and grading |
| `question.md` | The task, exam style |
| `solution.md` | Step-by-step walkthrough with a submit loop |
| `prerequisites.md` | Assumed knowledge and what the environment provides |
| `bootstrap/` | Environment preparation run once at startup |
| `manifests/` | Starting state applied by the bootstrap |
| `solution/` | Reference solution used by `astrona test` |
| `validation/` | Grading scripts, one per check; they read the archive with `tar tzf` |
