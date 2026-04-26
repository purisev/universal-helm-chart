# 008 — Multi-provider monitoring matrix

- **Status:** Accepted (introduced by commit `bf668bc`)
- **Date:** 2025-04-25

## Context

Two Prometheus-compatible monitoring stacks dominate Kubernetes deployments:

- **Prometheus Operator** — exposes `monitoring.coreos.com/v1` `ServiceMonitor` and `PodMonitor` CRDs.
- **VictoriaMetrics Operator** — exposes `operator.victoriametrics.com/v1beta1` `VMServiceScrape` and `VMPodScrape` CRDs (intentionally compatible shape, different API group).

In addition, both stacks can also discover scrape targets via **annotations** on the Service or Pod (`prometheus.io/scrape`, `prometheus.io/port`, `prometheus.io/path`) when the Prometheus / vmagent server is configured with `kubernetes_sd_configs` and the right relabel rules. Annotation-mode discovery doesn't need a CRD — a useful escape hatch in clusters that haven't installed an operator.

Finally, a workload may want its scrape target on the **Service** (for Deployments and StatefulSets with a stable Service) or on the **Pod** (for jobs that don't have a Service, or workloads where pod-level addressing is preferred).

We need one mental model that covers **two providers × two discovery modes × two target shapes = eight combinations**, with sensible defaults and per-workload override.

## Decision

A three-axis matrix, configured at `integrations.monitoring.defaults` and overridable per workload at `deployments.<name>.metrics.*` (or `statefulSets.<name>.metrics.*`):

| Axis        | Values                          | Default       |
|-------------|----------------------------------|---------------|
| `provider`  | `prometheus` \| `victoriametrics` | `prometheus`  |
| `discovery` | `crd` \| `annotations`            | `crd`         |
| `type`      | `service` \| `pod`                | `service`     |

What each combination renders:

- `prometheus` × `crd` × `service` → `ServiceMonitor`
- `prometheus` × `crd` × `pod` → `PodMonitor`
- `victoriametrics` × `crd` × `service` → `VMServiceScrape`
- `victoriametrics` × `crd` × `pod` → `VMPodScrape`
- `*` × `annotations` × `service` → `prometheus.io/*` annotations on the Service
- `*` × `annotations` × `pod` → `prometheus.io/*` annotations on the Pod template

Defaults at `integrations.monitoring.defaults` apply to every workload; per-workload values at `deployments.<name>.metrics.*` always win. The `enabled` switch defaults to `false` (workloads must opt in) — explicit opt-in keeps unscraped workloads off the monitoring radar by default.

Auxiliary fields (`port`, `path`, `scheme`, `interval`, `scrapeTimeout`, `relabelConfigs`, `basicAuth`, `headers`) are common to all combinations and override per-workload too.

## Consequences

**What this enables:**

- One chart works in clusters running Prometheus Operator, VictoriaMetrics, both, or neither (annotations mode).
- A team migrating from Prometheus to VictoriaMetrics flips one value (`provider: victoriametrics`) for the whole release without rewriting CRDs.
- Per-workload override gives one app two scrape configs if needed (e.g. main port via CRD, sidecar port via annotations on the Pod).

**What it costs:**

- Annotation-mode discovery requires `prometheus.io/port` to be **numeric** (the annotation contract). Setting `metrics.port` to a port name (which `crd` mode requires) is rejected by the schema in annotations mode. The chart applies a fallback: if `metrics.port` is unset in annotations mode, it uses `service.targetPort` or omits the annotation entirely. See `values.yaml:329–340` for the full narrative.
- The CRD-mode `port` field expects a port **name**, not a number. Users hitting this for the first time get a CRD validation error; the schema documents the constraint at `values.schema.json` (search for `discovery`).
- Two CRD groups must be tracked for compatibility (`monitoring.coreos.com` and `operator.victoriametrics.com`). [03-reference/03-compatibility.md](../03-reference/03-compatibility.md) lists the tested versions.

## Default behaviour

Defaults aim for the common case: Prometheus Operator-based cluster, scrape via CRD, target the Service. A typical workload only needs:

```yaml
deployments:
  api:
    service:
      ports:
        http: { port: 80, targetPort: 8080 }
        metrics: { port: 9090, targetPort: 9090 }
    metrics:
      enabled: true
      port: metrics       # name from service.ports above
```

## Alternatives considered

- **Prometheus only.** Rejected: VictoriaMetrics is widely deployed for cost / retention reasons.
- **Annotations only.** Rejected: CRD-driven discovery is the modern default; annotation-mode is a compatibility option.
- **A single `monitoring.kind` enum (`ServiceMonitor` / `PodMonitor` / `VMServiceScrape` / `VMPodScrape` / `annotations-service` / `annotations-pod`).** Rejected: hides the orthogonal axes; harder to override one without restating the others.

## References

- Commit `bf668bc` — "feat(monitoring): multi-provider scrape support (2.0.0)"
- `values.yaml:318–379` — `integrations.monitoring.defaults`
- `templates/servicemonitor.yaml`, `templates/podmonitor.yaml`
- `templates/_helpers.tpl` — `uhc.metricsProvider`, `uhc.metricsDiscovery`, `uhc.metricsTargetType`, `uhc.metricsExposeService`
- Tests: `tests/servicemonitor_test.yaml`, `tests/podmonitor_test.yaml`, `tests/metrics_annotations_test.yaml`
- Related: [ADR 006](006-integrations-namespace.md), [ADR 016](016-metrics-port-auto-exposure.md)
