# 016 — Metrics port auto-exposure on Service

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

Most apps don't expose `/metrics` on the same port as their main API:

- **Security.** The metrics endpoint shouldn't be reachable from `Ingress`. Splitting the port keeps it cluster-internal by default.
- **Allowed-hosts middleware.** Django, Spring, FastAPI all have host-validation middleware. Mounting the metrics path on the API port forces relaxing the middleware for in-cluster scrape probe IPs — a common source of audit findings.
- **Scrape isolation.** A 503-storm from a misbehaving app shouldn't impact metrics scraping; running them on different processes / sockets gives that for free.

The mechanical consequence: the chart needs a "metrics" port on the Service, with a matching `containerPort` in the pod template. Users who manage this manually end up writing the same port-pair declaration on every workload. The boilerplate is small but multiplied by the number of workloads.

A second concern: some workloads have **no main Service** at all (a pure batch worker, a gRPC client). They still want to expose `/metrics`. A monitoring-only Service is the right shape.

## Decision

A single switch at `integrations.monitoring.defaults.exposeService.enabled: true` (overridable per workload via `metrics.exposeService.enabled`) auto-emits the metrics port. The chart's behaviour is:

- **Workload has a main Service** (`service.enabled: true` and at least one entry in `service.ports`): append a `metrics` port to the Service's `ports[]` and a matching `containerPort` to the pod template. Port name is fixed as `metrics` (Kubernetes convention).
- **Workload has no main Service**: emit a **dedicated** Service with only the metrics port. Name: `<release-fullname>-<workload>-metrics`. This Service is also picked up by the ServiceMonitor / VMServiceScrape (when CRD discovery + service target is selected — see [ADR 008](008-multi-provider-monitoring.md)).
- **`metrics.type: pod`**: this whole feature is skipped. PodMonitor / VMPodScrape don't need a Service — the scrape happens directly against pod IPs.
- **`service.ports.metrics` already declared**: the auto-injection is skipped to avoid a duplicate port. The user's explicit declaration wins.

The metrics port is always rendered last in any `ports[]` list — see [ADR 014](014-deterministic-ordering.md) for the http-first / metrics-last rule.

Defaults at `integrations.monitoring.defaults.exposeService`:
```yaml
enabled: false        # opt-in
port: 9090            # ServicePort
targetPort: 9090      # containerPort
```

## Consequences

**What this enables:**

- One flag (`integrations.monitoring.defaults.exposeService.enabled: true` plus `metrics.enabled: true` per workload) gets a fully-wired metrics port on Service, pod template, and ServiceMonitor / VMServiceScrape.
- Pure batch workers can be scraped via a metrics-only Service without a main Service.
- The "metrics is not on http" pattern is easy to do right and hard to do wrong.

**What it costs:**

- When a user declares `service.ports.metrics` explicitly, they may not realise they've disabled the auto-exposure feature (the chart doesn't emit two ports). The skipping rule is documented next to the `integrations.monitoring.defaults.exposeService` block in `values.yaml`.
- The dedicated metrics-only Service for service-less workloads adds an object that an inattentive operator might miss. We accept this — it matches the intuition that "every scrape target has a Service."
- The fixed port name `metrics` is a chart convention. Users with idiosyncratic monitor configs that target other names must declare the port manually in `service.ports` instead.

## Worked example

```yaml
integrations:
  monitoring:
    defaults:
      enabled: true
      exposeService:
        enabled: true
        port: 9090
        targetPort: 9090

deployments:
  api:
    service:
      ports:
        http:
          port: 80
          targetPort: 8080
    # No explicit metrics port; auto-injection adds one
    metrics:
      enabled: true
  batch:
    service:
      enabled: false       # no main Service — but metrics scraping still wanted
    metrics:
      enabled: true
      type: service        # explicit: a metrics-only Service is rendered
```

Result:

- `<release>-api` Service with two ports: `http` (80) and `metrics` (9090).
- `<release>-batch-metrics` Service with one port: `metrics` (9090).
- ServiceMonitor / VMServiceScrape per workload, targeting the `metrics` port name.

## Alternatives considered

- **Always require explicit declaration.** Rejected: the boilerplate costs scale with workload count and the right shape is the same every time.
- **Auto-expose on the main port if no metrics port declared.** Rejected: hides the security / middleware caveats described in Context.
- **Configurable port name.** Rejected: `metrics` is the de-facto Kubernetes convention; supporting other names invites ServiceMonitor configuration drift.

## References

- `values.yaml` — the `integrations.monitoring.defaults.exposeService` block.
- `templates/service.yaml` — port injection (the metrics port lands last).
- `templates/_metrics.tpl` — `uhc.metricsExposeService`.
- Tests: `tests/service_test.yaml`, `tests/fixtures/service-existing-metrics-port.yaml`.
- Related: [ADR 006](006-integrations-namespace.md), [ADR 008](008-multi-provider-monitoring.md), [ADR 014](014-deterministic-ordering.md).
