# Question

Solve this question on: `terminal`

**Time:** about 35 minutes · **Weight:** Troubleshooting the Mesh Data Plane

## Scenario

Astronaut, nothing in the namespace `logcapstone-demo` works. According to the team's documentation, the intent is:

- all traffic between workloads is **encrypted** with mutual TLS (mTLS);
- `notification-service` accepts `POST` and refuses every other method.

Both pods are `2/2 Running`. The application logs are empty.

There are **two** independent faults, and the second one hides behind the first: until you fix the first, you cannot see the second. Work them in order.

## Your task

1. Read the access log on **both** proxies and write down the first signature: the response flag, whether an upstream address is present, and which side logged nothing.
2. Fix the first fault, then repeat step 1. The signature will have changed; read the new one, including the response code details.
3. Fix the second fault so the documented intent holds.

## Constraints

- **The `PeerAuthentication` must stay `STRICT`.** Relaxing it makes the first symptom disappear by accepting plain text, and is marked wrong.
- Do not delete the `DestinationRule` `notification`. It carries a connection pool setting (`connectionPool.tcp.maxConnections`) the platform team needs. Change only what is wrong.
- Do not delete the `AuthorizationPolicy` `notification-allow`, and do not widen it to allow every method. It must stay an `ALLOW` policy that selects the `notification-service` pods.
- Do not change the Deployments, the Service or the `tester` pod.

## Done when

- A `POST` from `tester` to `http://notification-service/notify` returns `200`.
- A `GET` from `tester` to the same address returns `403`.
- The `PeerAuthentication` `default` is still `STRICT`, the client no longer disables TLS, and the connection pool setting is still there.
- The `AuthorizationPolicy` `notification-allow` permits exactly `POST`.
- The destination proxy reports `connection_security_policy="mutual_tls"`, and no plain-text (`none`) traffic.
