# Question

Solve this question on: `terminal`

**Time:** about 20 minutes · **Weight:** Troubleshooting the Mesh Data Plane

## Scenario

The namespace `portproto-demo` runs two versions of `notification-service` behind one Service. `v1` answers `["EMAIL"]`; `v2` answers `["EMAIL","SMS"]`. A `DestinationRule` defines the subsets `v1` and `v2`, and a `VirtualService` sends requests with the header `testing: true` to `v2` and everything else to `v1`.

The team says the routing is ignored: requests with the header still reach both versions.

```sh
kubectl -n portproto-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 10); do curl -s -X POST -H "testing: true" http://notification-service/notify; echo; done' | sort -u
```

## Your task

In the namespace `portproto-demo`:

1. Find out from the `tester` proxy's own configuration why the `VirtualService` does not apply. Name the stage where the HTTP routing is missing.
2. Fix the cause so that the existing routing applies.

## Constraints

- Do not change, delete or recreate the `VirtualService` or the `DestinationRule`. They are correct.
- Do not change the Deployments or the `tester` pod.
- `notification-service` must stay on port `80` with target port `8084`. Fix how the port is *declared*, not which port it is.

## Done when

- The `notification-service` port declares an HTTP protocol, by its name (such as `http`) or by `appProtocol`, and still maps `80` to `8084`.
- The `tester` proxy holds an HTTP route for `notification-service` whose first rule matches the `testing` header.
- Ten requests with `testing: true` all answer `["EMAIL","SMS"]`, and ten requests without the header all answer `["EMAIL"]`.
