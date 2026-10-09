# Question

Solve this question on: `terminal`

Astronaut, three teams have each written a flight plan for the same beacon, and the signals now fly wherever the merge sends them. Istio 1.30.5 is installed.

Over the past year, three teams have each added a `VirtualService` for `notification-service` in the namespace `routing-demo`. `v1` answers `["EMAIL"]` and `v2` answers `["EMAIL","SMS"]`.

The intended behaviour, written in three separate tickets, is:

| Request | Should reach |
| --- | --- |
| carries the header `testing: true` | `v2` |
| path starts with `/priority` | `v2` |
| anything else | `v1` |

None of it works reliably. `istioctl analyze` reports only `Warning`s, and restarting the workloads changes nothing.

## Your task

In the namespace `routing-demo`:

1. Find out how many objects claim the host, and what the proxy's route table really contains. Do not trust any single YAML file.
2. Merge the routing so all three intended behaviours hold.

## Constraints

- **Exactly one `VirtualService` may claim `notification-service` on the mesh gateway** (no `gateways:` field, or `mesh`) when you are done.
- Do not change the `DestinationRule`, the Deployments, the Service or the `tester` pod.
- Tell the cases apart only by the header and the path prefix. Do not change what the versions return.

## Done when

All requests are sent as `POST` from the `tester` pod:

- Ten requests in a row to `http://notification-service/notify` with `testing: true` all return `["EMAIL","SMS"]`.
- Ten requests in a row to `http://notification-service/priority` all return `["EMAIL","SMS"]`.
- Ten requests in a row to `http://notification-service/notify` without the header all return `["EMAIL"]`.
- `istioctl analyze -n routing-demo` reports no `IST0109`, and one object owns the host.
