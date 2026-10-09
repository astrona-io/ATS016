# Summary

A `VirtualService` can be valid on its own and still send requests to the wrong place. This module showed the two mistakes behind most of these cases, and how to prove which one you have from the proxy itself.

## What you learned

`istiod` turns a `VirtualService` into Envoy route configuration. There is one route configuration per port, named after the port (`80`), with one virtual host per destination host. Each virtual host holds your `http` rules as an ordered list. The sidecar proxy of the client checks that list from the top, and the first match wins; there is no ranking by how specific a rule is. A rule with no `match` becomes a prefix match on `/`, which is true for every request. Every rule below it is shadowed and never checked. The apply still succeeds; the only signs are a `Warning` line from the validating webhook and `Warning [IST0130]` from `istioctl analyze`. A rule with no effect at all is usually never reached, while a rule that partly works usually has a wrong match.

Matches have exact rules of their own. Conditions inside one `match` entry must all hold, while any one entry in the `match` list is enough. Header names must be lower case, header values are case-sensitive, and a value such as `"true"` must be quoted, or the API server rejects the object.

Two `VirtualService` objects that claim the same host in the mesh scope are not merged for the sidecar proxies. The proxy uses one of them and drops the other, and nothing in your YAML decides which one. `istioctl analyze` reports this as `Error [IST0109]`, even though `kubectl apply` accepted both objects. The rule is one object per host per gateway scope. Objects bound to different gateways do not conflict, gateways can merge fragments for one host, and delegation through `spec.http[].delegate` is the planned way to share one host's routing.

The route table is the ground truth. `istioctl proxy-config routes deploy/tester -n conflict-demo --name 80 -o json` shows what the client's proxy really holds; the table output hides matches as `/*`. The key facts to remember are these:

- Put the specific matches first and the unconditional route last.
- Leave exactly one `VirtualService` per host in each gateway scope.
- Ask the proxy of the client, because it makes the routing decision.
- Prove a routing fix on every path, with ten requests each, then check `istioctl analyze` and the route table again.

<!-- astrona:playground:destroy -->
