# Capstone: Repair A Namespace Nothing Validates

**Time:** about 35 minutes · **Weight:** Troubleshooting Configuration
**Covers:** module 1 (`istioctl analyze`) and module 2 (`istioctl x describe pod`)

## Scenario

`audit-demo` was set up in a hurry before a compliance review. Everything in it
applied without a single error, and the team believes the namespace is:

- in the mesh,
- routing traffic to a defined subset,
- restricted so that only `POST` is permitted on `notification-service`.

The reviewer disagrees on all three counts and has asked you to prove the state
of the namespace rather than describe the intent.

## Your task

Bring `audit-demo` to the state its authors believed it was already in.

1. Use the tool that reads configuration the way `istiod` does to enumerate
   every finding — `Error`, `Warning` **and** `Info`. Several problems here are
   not Errors.
2. Use the tool that summarises everything applying to one workload to confirm
   what the policy actually does, and to what.
3. Fix every fault so the namespace's behaviour matches the intent.

## Constraints

- **Route only to subsets that exist and select running pods.** Do not invent a
  subset, and do not create a `Gateway` to satisfy a dangling reference.
- The `AuthorizationPolicy` must end up **effective** and must still permit only
  `POST`. Do not delete it and do not widen it to allow everything.
- Do not modify the Deployment container spec, the Service, or the `tester`
  pod's container.

## Done when

- `istioctl analyze -n audit-demo` reports **no** `Error` and **no** `Warning`.
- The namespace is labelled for injection and every workload carries an
  `istio-proxy` container.
- The `AuthorizationPolicy` selects `notification-service` and lists exactly the
  `POST` method.
- A `POST` from `tester` returns `200`; a `GET` returns `403`.
