# 08 — KEDA event-driven autoscaling

A Kafka consumer that scales 1 → 30 replicas based on consumer-group lag, plus VPA in `Initial` mode for right-sized memory requests on first pod start.

## What this shows

- `keda.enabled: true` on the worker, with a `kafka` trigger keyed on consumer-group lag.
- `minReplicas: 1`, not `0` — this worker should never have a gap in consumption. Set `minReplicas: 0` instead when the workload can tolerate sitting idle (e.g. a `cron` trigger active only during a scheduled window); KEDA scales it down to zero once every trigger goes inactive, and back up once one fires again.
- `hpa.enabled: false` (default) — KEDA itself manages an internal HPA; mixing both would be rejected by the chart's mutual-exclusion guard.
- `verticalPodAutoscaler.enabled: true` with `updateMode: Initial` — VPA sets the resource request the first time each pod is created. Works alongside KEDA because VPA touches `requests`, KEDA touches `replicas`. ([ADR 007](../../05-adr/007-autoscaler-mutual-exclusion.md))
- `service.enabled: false` — pure consumer, no inbound traffic.
- `metrics.type: pod` + `integrations.monitoring.defaults.exposeService.enabled: true` → a metrics-only Service `<release>-worker-metrics` is auto-emitted, and a `PodMonitor` scrapes the worker pods directly.
- The Deployment manifest will have **no `spec.replicas`** because an HPA-class scaler is on — so Helm `upgrade` doesn't bounce the count back to a static value on every sync.

## Delta from `02-web-app-ingress`

| Changed | What |
|---------|------|
| HPA → KEDA | Event-driven scaling; HPA off, KEDA on. |
| Added VPA | Orthogonal, recommends/sets memory requests on initial pod create. |
| Service off | Worker has no listener; metrics-only Service auto-emitted instead. |
| `metrics.type: pod` | PodMonitor instead of ServiceMonitor. |
| Removed Ingress | No external traffic. |

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

- KEDA installed in the cluster (`keda.sh` CRDs).
- VPA installed (`autoscaling.k8s.io` CRDs).
- A Kafka cluster reachable at `kafka.kafka:9092` with topic `orders` and consumer group `orders-worker`. Adjust to your environment.
- Prometheus Operator CRDs for the PodMonitor (or remove the `metrics:` block).

## Related ADRs

- [ADR 007 — Autoscaler mutual exclusion](../../05-adr/007-autoscaler-mutual-exclusion.md)
- [ADR 016 — Metrics port auto-exposure](../../05-adr/016-metrics-port-auto-exposure.md)
