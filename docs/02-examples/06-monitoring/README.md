# 06 — Monitoring (Prometheus + VictoriaMetrics, Service + Pod targets)

Three workloads exercising the monitoring matrix:

- `api` — Prometheus `ServiceMonitor` (CRD discovery + service target).
- `worker` — Prometheus `PodMonitor` (CRD discovery + pod target). No Service.
- `legacy` — annotations-mode (`prometheus.io/scrape` etc.) for clusters that haven't installed Prometheus Operator CRDs.

Plus chart-level `exposeService.enabled: true` so metrics ports are auto-emitted on Services that don't declare one.

## What this shows

- `integrations.monitoring.defaults` sets Prometheus + CRD + service as the cluster default.
- Per-workload `metrics.*` overrides every axis individually:
  - `api` accepts the defaults (single value: `metrics.enabled: true`).
  - `worker` switches `type: pod` to emit a `PodMonitor` instead.
  - `legacy` switches `discovery: annotations` to skip the CRD entirely.
- **Auto-exposed metrics port** on `api` (`exposeService.enabled: true` with no explicit `service.ports.metrics`).
- **Metrics-only Service** for `worker` because its `service.enabled: false` — the chart still emits a `<release>-worker-metrics` Service so the PodMonitor's port name resolves cleanly.
- A `victoriametrics-flavoured` workload showing the per-workload provider override.

## Delta from `02-web-app-ingress`

| Changed | What |
|---------|------|
| `integrations.monitoring.defaults` | Set chart-level monitoring defaults explicitly. |
| Three workloads | One per discovery/target combination. |
| `metrics.exposeService.enabled` | Enabled chart-wide so the metrics port lands automatically where applicable. |
| `metrics.type: pod` on `worker` | PodMonitor instead of ServiceMonitor. |
| `metrics.discovery: annotations` on `legacy` | Bare Prometheus annotations on the Service. |
| `metrics.provider: victoriametrics` on `vm-flavoured` | Per-workload provider override (emits `VMServiceScrape` instead of `ServiceMonitor`). |

## Files

| File | Purpose |
|------|---------|
| [`values.yaml`](values.yaml) | Chart values. |
| [`argocd/application.yaml`](argocd/application.yaml) | Argo CD `Application`, single source. |
| [`argocd/application-multisource.yaml`](argocd/application-multisource.yaml) | Argo CD `Application` with `spec.sources[]`. |
| [`flux/ocirepository.yaml`](flux/ocirepository.yaml) | Flux `OCIRepository`. |
| [`flux/helmrelease.yaml`](flux/helmrelease.yaml) | Flux `HelmRelease`. |
| [`helm/install.sh`](helm/install.sh) | Plain `helm upgrade --install`. |

## Try it

```bash
bash helm/install.sh
kubectl apply -f argocd/application.yaml -n argocd
kubectl apply -f flux/
```

## Prerequisites

- Prometheus Operator CRDs (`monitoring.coreos.com`) installed for `ServiceMonitor` / `PodMonitor` to materialise.
- VictoriaMetrics Operator CRDs (`operator.victoriametrics.com`) installed for the `vm-flavoured` workload's `VMServiceScrape`. Remove the `vm-flavoured` workload if VM Operator isn't present.
- Prometheus / vmagent configured to discover the right CRDs / pick up annotations.

## Related ADRs

- [ADR 008 — Multi-provider monitoring matrix](../../05-adr/008-multi-provider-monitoring.md)
- [ADR 016 — Metrics port auto-exposure](../../05-adr/016-metrics-port-auto-exposure.md)
