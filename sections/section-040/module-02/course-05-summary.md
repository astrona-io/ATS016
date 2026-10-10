# Summary

A `503` on its own says that a request failed, not who failed it. This module traced one `503` from its response flag to the missing link in the proxy's configuration, fixed the correct end, and then looked at a quieter cause of ignored routing.

## What you learned

The first question about a `503` is who answered. The client proxy's access log holds the response flag: `NC` means the route named a cluster that does not exist, `UH` means the cluster has no usable endpoints, `NR` means no route matched, `UF` and `UC` mean the connection to the destination failed or was closed, and `-` means the application produced the status itself. When the client log shows a failure and the destination proxy's log has no line for the request, the request never arrived, and the investigation stays on the sending side.

`istioctl analyze` often names the fault in one line, such as `IST0101` for a `VirtualService` that refers to a subset no `DestinationRule` defines. The chain still matters, because it reads what the proxy actually runs: the route gives the exact cluster name, the cluster list shows whether that cluster exists, and the endpoint list shows whether it has pods behind it. A missing cluster and an empty cluster look the same at the endpoint stage, so the cluster check is not optional.

A broken reference is fixed in the direction that matches what is deployed. Adding a subset whose labels match no pod quiets the analyzer and turns `NC` into `UH`, which is harder to diagnose. A fix is proven three ways: a real request, the proxy's route table, and a clean analyzer run. The access log confirms it best, with the flag `-` and an upstream host address where there was none.

Istio reads a Service port's protocol from `appProtocol`, then from the port name in the form `<protocol>[-<suffix>]`, and otherwise uses automatic detection, which works for plain HTTP. A port declared as `tcp` gets no route stage, so every HTTP rule for it is ignored while requests still return `200`. The key facts to remember are these:

- Read the client proxy's response flag before you open any configuration.
- Copy the cluster name from the route output, quoted, with empty fields kept.
- Check the running pods before you create a subset.
- When a rule is ignored rather than wrong, check whether the listener hands off to a `Route:`.

<!-- astrona:playground:destroy -->
