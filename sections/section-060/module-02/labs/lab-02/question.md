# Question

Solve this question on: `terminal`

**Time:** about 25 minutes · **Exam topic:** Troubleshooting the Mesh Data Plane

## Scenario

Two teams call `notification-service` in the namespace `callers-demo`. The `orders` team says everything works. The `reports` team says requests "fail now and then". Both teams blame `notification-service`.

The namespace runs `notification-service-v1` behind the Service `notification-service` on port `80`, two client Deployments, `orders-client` and `reports-client`, that send requests to it all the time, and a `tester` client pod with `curl`. Prometheus is installed in `istio-system` and answers inside the cluster at `http://prometheus.istio-system:9090`.

## Your task

In the namespace `callers-demo`:

1. With PromQL queries over `istio_requests_total`, find which client workload gets `5xx` responses. Do not count `curl` output by hand.
2. Find which value of the `reporter` label records those errors, and which response flag the proxy wrote for them.
3. Record your findings in a ConfigMap named `findings` in `callers-demo`, with exactly these keys:
   - `failing-caller`: the name of the client workload that gets the errors
   - `reporter`: `source` or `destination`
   - `response-flag`: the response flag of the failed requests
4. Find the cause and remove it, so that both clients get `200` again.

## Constraints

- Do not delete the `VirtualService` named `notification`. It must still route `notification-service` when you are done; remove only what causes the errors.
- Do not modify the Deployments, the Service or the `tester` pod.
- Measure before you fix. Once the cause is gone, the evidence fades from a one-minute rate window.

## Done when

- The Prometheus pod is `Running`.
- The ConfigMap `findings` holds the correct `failing-caller`, `reporter` and `response-flag`.
- The `VirtualService` `notification` still routes `notification-service` and has no `fault` block.
- Ten `POST` requests from `reports-client` and ten from `orders-client` all return `200`.
