# Task: An Empty Graph And A Red Badge

**Time:** about 20 minutes · **Weight:** Troubleshooting Configuration

## Scenario

Kiali and Prometheus are installed. A colleague opened the Kiali graph for
`kiali-demo`, saw nothing at all, and filed a ticket saying "the mesh is down".

Separately, Kiali's **Istio Config** view shows a red validation badge on one of
the namespace's objects.

## Your task

In the namespace `kiali-demo`:

1. Explain why the graph is empty, and make it non-empty. The mesh is not down.
2. Find the object Kiali's validation view flags, and confirm the same findings
   from the command line. Then fix them so validation is clean.
3. Confirm both of Kiali's data sources are healthy, and be able to say what
   each one contributes.

## Constraints

- Do not uninstall or reinstall the addons.
- The remaining routing must still send traffic to `notification-service` — do
  not fix the validation errors by deleting every routing object and leaving the
  namespace unrouted.
- Any subset a route names must be defined and select at least one running pod.

## Done when

- The Prometheus and Kiali pods are `Running`.
- `istioctl analyze -n kiali-demo` reports no findings.
- Request metrics exist for the `tester` → `notification-service` edge, so the
  graph has something to draw.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Common problems: network issues](https://istio.io/latest/docs/ops/common-problems/) — the catalogue of 503 causes and how to tell them apart
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
