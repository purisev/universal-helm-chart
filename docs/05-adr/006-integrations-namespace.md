# 006 — `integrations` namespace for ecosystem knobs

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

The chart sits in an ecosystem of controllers that consume or annotate workload resources: Argo CD (sync waves, ImageUpdater), Stakater Reloader (auto-restart on ConfigMap/Secret change), External Secrets Operator (ESO — `SecretStore`, `ExternalSecret`), Prometheus Operator and the VictoriaMetrics Operator (scrape CRDs), KEDA (event-driven autoscaling).

Each integration introduces a couple of values keys: a master switch, some configuration, and CRD-shaped sub-resources. Pre-2.0.0 these accumulated at the top level of `values.yaml`: `argocdSyncWaves: …`, `reloader: enabled`, `secretStores: …`, `externalSecrets: …`, `serviceMonitorEnabled: …`. The result was a ~50-key-deep root, where unrelated controllers' switches lived next to each other and there was no common shape for "is this integration on?"

## Decision

Group all ecosystem knobs under a single top-level `integrations:` block, with one sub-section per integration. Every integration provides a master `enabled` switch, configuration fields, and (where relevant) CRD-shaped resources.

```yaml
integrations:
  argocd:
    syncWaves:
      enabled: true                       # see ADR 010 for the default wave map
    imageUpdater:
      enabled: false                      # see values.yaml for full Image Updater config
  stakater:
    reloader:
      enabled: false                      # see ADR 017
  eso:
    enabled: true
    secretStores: {}                      # map; see ADR 015
    externalSecrets: {}                   # map; see ADR 015
  monitoring:
    defaults:
      enabled: false                      # see ADR 008 / ADR 016
```

The `customize.labels` and `customize.annotations` sub-blocks under each integration's resources allow users to inject extra metadata onto the resources that integration owns (e.g. add a Reloader strategy annotation onto a ConfigMap). This is the same shape across integrations.

## Consequences

**What this enables:**

- **Discoverability.** A reader scanning `values.yaml` sees one block listing every external system the chart knows about. Anything outside this block is "core Kubernetes only".
- **Uniform on/off semantics.** `integrations.eso.enabled: false` short-circuits all ESO rendering even if `secretStores` or `externalSecrets` entries are declared — useful for "park the configuration" in environments where ESO is not installed.
- **Adding a new integration is a contained change.** A new sub-section under `integrations` plus the templates that consume it; no top-level churn.
- **Schema clarity.** Each integration's schema is one named object — easy to validate strictly. See [ADR 013](013-schema-driven-validation.md).

**What it costs:**

- The values paths are deeper: `integrations.monitoring.defaults.provider` instead of `monitoringProvider`. Overlay values verbose ratio goes up. We accept this in exchange for the discoverability benefit.
- Renaming was a 2.0.0 breaking change. Pre-2.0.0 paths do not work; this is captured in the chart version bump.

## Alternatives considered

- **Top-level keys per integration (`reloader: …`, `eso: …`, `monitoring: …`).** Rejected: pre-2.0.0 status quo. Top-level becomes noisy and there's no obvious place for new integrations.
- **A single top-level `enabled` block listing per-integration toggles, with each integration's config under a separate top-level key.** Rejected: separates the on/off switch from the config, making it possible to enable an integration with no config and vice versa.
- **Integration-specific sub-charts.** Rejected: would re-create the dependency-graph fragility we avoid by having one chart ([ADR 001](001-universal-chart-scope.md)).

## References

- `values.yaml` — the `integrations:` block.
- `values.schema.json` — the `integrations` object definition.
- Related: [ADR 008](008-multi-provider-monitoring.md), [ADR 010](010-argocd-sync-waves.md), [ADR 015](015-eso-data-vs-datafrom.md), [ADR 016](016-metrics-port-auto-exposure.md), [ADR 017](017-reloader-annotation-injection.md).
