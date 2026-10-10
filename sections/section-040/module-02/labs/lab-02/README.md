---
estimated_duration: 20m
---

# Declare The Service Port Protocol So The Route Applies

- **ID:** LAB
- **Slug:** ats-016-lab-040-02-02
- **Author:** Paris Nakita Kejser
- **Type:** Astrona graded lab

Graded lab for the namespace `portproto-demo`. The `notification-service` Service port is declared as TCP (`tcp-notify`), so the client proxy builds no HTTP route and the header-based `VirtualService` is ignored. The learner proves this from the proxy and fixes the port declaration. Read `question.md` for the task; `solution.md` is the walkthrough.

## Run it

```sh
astrona run -c .
astrona submit
astrona destroy ats-016-lab-040-02-02
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-016-lab-040-02-02`), not
the config path.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition, bootstrap and grading |
| `question.md` | The task, exam style |
| `solution.md` | Step-by-step walkthrough with a submit loop |
| `prerequisites.md` | Assumed knowledge and what the environment provides |
| `bootstrap/` | Environment preparation run once at startup |
| `manifests/` | Starting state applied by the bootstrap (`lab-start.yaml`, `routing.yaml`) |
| `solution/` | Reference solution used by `astrona test` |
| `testing/` | Waits for istiod before the reference solution runs |
| `validation/` | Grading scripts, one per check |
