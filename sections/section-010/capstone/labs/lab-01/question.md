# Question

Solve this question on: `terminal`

**Time:** about 35 minutes · **Exam topic:** Troubleshooting Configuration

## Scenario

The namespace `audit-demo` was set up in a hurry before a compliance review. Every object in it applied without an error, and the team believes the namespace is:

- in the mesh, with a sidecar proxy (Envoy) in every pod;
- routing traffic to a defined subset;
- restricted so that only `POST` is allowed on `notification-service`.

The reviewer disagrees on all three counts. They want you to prove the real state of the namespace, not describe what was intended.

## Your task

Bring `audit-demo` to the state its authors believed it was already in.

1. Use the tool that reads configuration the way `istiod` does to list every finding: `Error`, `Warning` **and** `Info`. Several problems here are not Errors.
2. Use the tool that summarises everything that applies to one workload to confirm what the policy actually does, and to which pods.
3. Fix every fault so the namespace behaves as intended.

## Constraints

- **Route only to subsets that exist and select running pods.** Do not invent a subset, and do not create a `Gateway` to satisfy a reference that points at nothing.
- The `AuthorizationPolicy` named `notification-post-only` must end up **effective** and must still allow only `POST`. Do not delete it, and do not widen it to allow everything.
- Do not change the Deployment's container spec, the Service, or the `tester` pod's container.

## Done when

- `istioctl analyze -n audit-demo` reports **no** `Error` and **no** `Warning`.
- The namespace is labelled for injection, and every running pod carries an `istio-proxy` container.
- The `AuthorizationPolicy` selects running `notification-service` pods and lists exactly the `POST` method.
- A `POST` from `tester` returns `200`, and a `GET` returns `403`.
