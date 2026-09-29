# Capstone: Consolidate Three Claimants Into One Route Table

**Time:** about 30 minutes · **Weight:** Troubleshooting Configuration
**Covers:** module 1 (conflicting and shadowed routes), end to end

## Scenario

Three teams have each added a `VirtualService` for `notification-service` in
`routing-demo` over the past year. `v1` answers `["EMAIL"]`; `v2` answers
`["EMAIL","SMS"]`.

The intended behaviour, as written in three separate tickets, is:

| Request | Should reach |
| --- | --- |
| carries header `testing: true` | `v2` |
| path starts with `/priority` | `v2` |
| anything else | `v1` |

None of it works reliably. `istioctl analyze` reports only `Warning`s, and
restarting the workloads changes nothing.

## Your task

In the namespace `routing-demo`:

1. Establish how many objects claim the host and what the proxy's route table
   actually contains. Do not trust any single YAML file.
2. Consolidate the routing so the three intended behaviours all hold.

## Constraints

- **Exactly one `VirtualService` may claim `notification-service` on the mesh
  gateway** when you are done.
- Do not modify the `DestinationRule`, the Deployments, the Service or the
  `tester` pod.
- Do not distinguish the cases by anything other than the header and the URI
  prefix — no changes to what the versions return.

## Done when

- Ten consecutive requests with `testing: true` all return `["EMAIL","SMS"]`.
- Ten consecutive requests to `/priority` all return `["EMAIL","SMS"]`.
- Ten consecutive plain requests all return `["EMAIL"]`.
- `istioctl analyze -n routing-demo` reports no `IST0109`, and one object owns
  the host.

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Configuration analysis messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and the workflow around them
- [Destination rule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the traffic objects a broken route points at
