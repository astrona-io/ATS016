---
estimated_duration: 25m
---

# Find Which Caller Is Failing With PromQL

- **ID:** LAB
- **Slug:** ats-016-lab-060-02-02
- **Author:** Paris Nakita Kejser
- **Type:** Astrona graded lab

Graded lab for the namespace `callers-demo`. Two clients, `orders-client` and
`reports-client`, call `notification-service` in a loop; a `VirtualService`
aborts 25% of the requests from `reports-client` only. The learner finds the
affected caller with PromQL, records the caller, the reporter and the response
flag in a ConfigMap, and removes the fault while keeping the route. Read
`question.md` for the task; `solution.md` is the walkthrough.

## Run it

```sh
astrona run -c .
astrona submit
astrona destroy ats-016-lab-060-02-02
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-016-lab-060-02-02`), not
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
| `testing/` | Waits for istiod before `astrona test` applies the solution |
| `validation/` | Grading scripts, one per check |
