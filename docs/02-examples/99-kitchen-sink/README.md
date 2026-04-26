# 99 — kitchen sink

Everything-on showcase. **Don't deploy this verbatim** — it exists to demonstrate the chart's full surface in one place. Use it as a reading reference; copy individual sections into a real `values.yaml`.

## What this shows

- Two Deployments (`api`, `worker`) with sidecars and per-workload `inherit` opt-outs.
- One StatefulSet (`db`) with a `volumeClaimTemplate` and headless Service.
- Two `jobGroups`:
  - `migrations` — pre-install Job hook, tasks-mode initContainers, hashed-name idempotency.
  - `nightly` — CronJob.
- Service per Deployment with multi-port (`http`, `grpc`, `admin`, `metrics`) — port ordering exercises [ADR 014](../../05-adr/014-deterministic-ordering.md).
- Singleton `httpRoute` with parent Gateway + per-workload route shorthand and `priority`.
- Cross-namespace `referenceGrant`.
- Multi-Ingress map (`internal` + `external`).
- HPA on the API; KEDA `ScaledObject` on the worker (event-driven on a Kafka lag scaler); VPA on the database.
- `integrations.monitoring` with VictoriaMetrics provider, CRD discovery, plus an annotation-mode override for one workload.
- ESO `SecretStore` (Vault) and two `ExternalSecret`s — one with explicit `data`, one with `dataFrom`.
- Stakater Reloader on with the default `auto` strategy.
- Argo CD `ImageUpdater` in shorthand mode tracking the API image with `update-strategy: digest`.
- `commonLabels`, custom `podSecurityContext`, `automountServiceAccountToken: true` for the API (RBAC-bound), `NetworkPolicy`, `PodDisruptionBudget`, `topologySpreadConstraints`.

## Delta from `02-web-app-ingress`

This example doesn't follow the +1 progression — it's a leap to "everything". Read the values file with one ADR open per section:

| Section | Read first |
|---------|-----------|
| `deployments` / `statefulSets` | [ADR 002](../../05-adr/002-multi-workload-keyed-maps.md), [ADR 003](../../05-adr/003-layered-inheritance-and-override.md) |
| `jobGroups` | [ADR 005](../../05-adr/005-jobgroups-unification.md), [ADR 012](../../05-adr/012-job-spec-hashing-for-idempotency.md) |
| `integrations.argocd.syncWaves` (default) | [ADR 010](../../05-adr/010-argocd-sync-waves.md) |
| `integrations.monitoring` | [ADR 008](../../05-adr/008-multi-provider-monitoring.md), [ADR 016](../../05-adr/016-metrics-port-auto-exposure.md) |
| `integrations.eso` | [ADR 015](../../05-adr/015-eso-data-vs-datafrom.md) |
| `integrations.stakater.reloader` | [ADR 017](../../05-adr/017-reloader-annotation-injection.md) |
| `httpRoute` + `referenceGrant` + `ingresses` | [ADR 009](../../05-adr/009-dual-networking-stack.md) |
| `hpa` / `keda` / `verticalPodAutoscaler` | [ADR 007](../../05-adr/007-autoscaler-mutual-exclusion.md) |

## Files

| File | Purpose |
|------|---------|
| [`values.yaml`](values.yaml) | Chart values for this scenario. |
| [`argocd/application.yaml`](argocd/application.yaml) | Argo CD `Application`, single source. |
| [`argocd/application-multisource.yaml`](argocd/application-multisource.yaml) | Argo CD `Application` with `spec.sources[]`. |
| [`flux/ocirepository.yaml`](flux/ocirepository.yaml) | Flux `OCIRepository`. |
| [`flux/helmrelease.yaml`](flux/helmrelease.yaml) | Flux `HelmRelease`. |
| [`helm/install.sh`](helm/install.sh) | Plain `helm upgrade --install` (with a `--dry-run` flag enabled by default — copy and remove if you really want to install). |

## Prerequisites (CRDs)

Almost every CRD-bearing integration is touched. Don't apply this in a cluster missing any of:

- Gateway API (`gateway.networking.k8s.io`)
- Prometheus or VictoriaMetrics Operator (depending on which provider you keep enabled)
- External Secrets Operator (`external-secrets.io`)
- KEDA (`keda.sh`)
- VPA (`autoscaling.k8s.io`)
- Argo CD Image Updater
- Stakater Reloader
