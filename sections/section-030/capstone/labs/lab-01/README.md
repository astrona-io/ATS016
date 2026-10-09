# Capstone: Three Workloads, Three Different Control Plane Faults

- **ID:** CAPSTONE
- **Slug:** ats-016-capstone-030
- **Author:** Paris Nakita Kejser
- **Type:** Astrona graded lab

Graded lab for the namespace(s) `cpcapstone-demo`. Read `question.md` for the task; `solution.md` is the walkthrough.

## Run it

```sh
astrona run -c .
astrona submit
astrona destroy ats-016-capstone-030
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-016-capstone-030`), not
the configuration path.

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
| `validation/` | Grading scripts, one per check |
