# The Four-Stage Walk

You have now read each stage of a proxy's configuration on its own. In a real investigation you read them as one chain, and each stage gives a name to the next. This part turns the four stages into a procedure you can follow under time pressure, and maps each symptom to the stage that most likely produced it.

## The walk, as a procedure

Take one complaint: "requests to `notification-service` from `tester` are failing". Start on the **client** proxy, because the client's sidecar proxy makes the routing decision:

```text
   1. LISTENER   istioctl proxy-config listener deploy/tester -n <ns> --port 80
                 Is there an HTTP listener for that port?
                 No → the traffic is not handled as HTTP. Check the port protocol and exclusions.

   2. ROUTE      istioctl proxy-config route deploy/tester -n <ns> --name 80 -o json
                 Which cluster does the matching rule name? Which VirtualService produced it?
                 Note the EXACT cluster name: the next step needs it.

   3. CLUSTER    istioctl proxy-config cluster deploy/tester -n <ns> --fqdn <host>
                 Does that cluster exist?
                 No → a missing subset or host. Fix the reference.

   4. ENDPOINT   istioctl proxy-config endpoint deploy/tester -n <ns> --cluster "<name>"
                 Any endpoints? HEALTHY? OUTLIER CHECK OK?
                 Empty → selector, readiness, or subset labels. Removed → this client stopped using it.
```

If all four stages are correct on the client, the problem is on the far side. Move to the **destination** proxy:

```text
   5. INBOUND    istioctl proxy-config cluster deploy/<dest> -n <ns> | grep inbound
                 Is there an inbound|<port>|| cluster?

   6. POLICY     istioctl x describe pod <dest-pod> -n <ns>
                 Effective mTLS mode, and which AuthorizationPolicy selects it.

   7. EVIDENCE   kubectl logs <dest-pod> -c istio-proxy --tail=20
                 Did the request arrive at all?
```

Step 7 reads the destination's access log, where Envoy writes one line per request. It is also the cheapest step on the list. That is why, in a real incident, many people run it first and then use the configuration walk to explain what the log showed.

## Walk it once in your playground

Run the four client-side stages in order, and write down the name each stage gives to the next. Start with the listener on port 80, then read the route it hands off to:

<!-- astrona:playground:renew -->

```sh
istioctl proxy-config listener deploy/tester -n proxycfg-demo --port 80
istioctl proxy-config route deploy/tester -n proxycfg-demo --name 80 -o json \
  | grep -E '"name"|"prefix"|"cluster"' | head -20
```

You should see something like:

```text
ADDRESSES PORT MATCH                                DESTINATION
0.0.0.0   80   Trans: raw_buffer; App: http/1.1,h2c Route: 80
0.0.0.0   80   ALL                                  PassthroughCluster
        "name": "80",
                "name": "istio-egressgateway.istio-system.svc.cluster.local:80",
...
                "name": "notification-service.proxycfg-demo.svc.cluster.local:80",
                            "prefix": "/",
                                    "name": "testing",
                            "cluster": "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local",
                                        "name": "envoy.retry_host_predicates.previous_hosts",
                            "prefix": "/"
                            "cluster": "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local",
```

The output is shortened: the lines for the gateway virtual hosts are replaced by `...`.

The listener hands off to `Route: 80`, and both rules in that route name the cluster `outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local`. Copy that name exactly, because the next two stages need it. Check that the cluster exists, then ask what it resolves to:

```sh
istioctl proxy-config cluster deploy/tester -n proxycfg-demo \
  --fqdn notification-service.proxycfg-demo.svc.cluster.local
istioctl proxy-config endpoint deploy/tester -n proxycfg-demo \
  --cluster "outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local"
```

You should see something like:

```text
SERVICE FQDN                                             PORT     SUBSET     DIRECTION     TYPE     DESTINATION RULE
notification-service.proxycfg-demo.svc.cluster.local     80       -          outbound      EDS      notification.proxycfg-demo
notification-service.proxycfg-demo.svc.cluster.local     80       v1         outbound      EDS      notification.proxycfg-demo
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.8:8084     HEALTHY     OK                outbound|80|v1|notification-service.proxycfg-demo.svc.cluster.local
```

The `v1` cluster exists, and it has one `HEALTHY` endpoint that this proxy has not removed. Every link in the chain holds, which is what a working proxy looks like.

## Mapping a symptom to a stage

The response flag in the access log points straight at a stage. Together with the walk above, it turns a status code into a stage, and a stage into one command:

| Symptom | Most likely stage | Because |
| --- | --- | --- |
| traffic works but no metrics, no policy | **1, listener** | it was never captured, or it fell to passthrough |
| `404`, flag `NR` | **2, route** | a virtual host matched, but none of its rules |
| the wrong version answers | **2, route** | a rule matched, but not the one you meant |
| `503`, flag `NC` | **3, cluster** | the route named a cluster that does not exist |
| `503`, flag `UH` | **4, endpoint** | the cluster exists with nothing usable behind it |
| `503`, flag `UF` | inbound / mTLS | the connection could not be set up at the far end |
| `403` | inbound policy | an `AuthorizationPolicy` on the destination refused |

> [!TIP]
> Read the response flag before you open any configuration. A flag tells you which stage to check first, so the walk takes one command instead of four.

You can now walk the chain on the client, carrying the exact cluster name from the route to the cluster and endpoint stages, and move to the destination proxy when the client side holds. You can also map a response flag to the stage that produced it. What you have not done yet is build routing yourself and prove from the proxy that it landed, which is what the graded lab asks.

## Common pitfalls

> [!WARNING]
> - **Walking the stages out of order.** Each stage gives a name to the next. Skipping one means guessing the input to the step you jumped to.
> - **Dumping everything.** `proxy-config all`, or any subcommand without a filter, is thousands of lines on a real mesh. Narrow with `--fqdn`, `--port`, `--name` or `--cluster` from the start.
> - **Retyping the cluster name.** Copy it from the route output, empty fields included, and quote it.
> - **Stopping at the client when all four stages look right.** Then the problem is on the destination: its inbound cluster, its policy, or its access log.

## Your mission: Build The Routing, Then Prove It From The Proxy

You can now read every stage of a proxy's configuration and walk them as one chain. The graded lab asks you to write the subsets and a header route for two versions of `notification-service`, then prove from the `tester` proxy's own route table and endpoints that they landed.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-016-playground-040-01
```

Then start the lab:

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS016.git -c sections/section-040/module-01/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-040/module-01/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-016-lab-040-01
astrona start ats-016-playground-040-01
```
