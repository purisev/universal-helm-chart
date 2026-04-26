# 010 — Argo CD sync-waves baked in by default

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

Argo CD applies all manifests in a sync simultaneously by default, then waits for them to reconcile. For most charts that's fine. For a chart that emits a Deployment, an ExternalSecret feeding it, a ServiceAccount the Deployment runs as, an Ingress pointing at its Service, and a ServiceMonitor watching it, "all at once" produces noisy first-time syncs:

- The Deployment's pod fails to start because the ExternalSecret hasn't materialised the Secret yet.
- The Ingress is created before the Service backing it.
- The ServiceMonitor references a Service that hasn't been admitted.

These resolve themselves on retry, but the sync looks unhealthy for the first few seconds and the noise pollutes Argo CD's "out of sync" / "degraded" indicators.

Argo CD's mechanism for this is **sync waves** — `argocd.argoproj.io/sync-wave: "<n>"` annotations on each resource. Lower waves apply first; the controller waits for each wave to be Healthy before starting the next. The chart can either expect users to set waves themselves (rare — most won't) or supply sane defaults.

## Decision

Bake **sane sync-wave defaults into the chart**, controlled centrally at `integrations.argocd.syncWaves`. Each resource kind has a default wave; users can override any number, disable any one (set to `null` to omit only that kind's annotation), or disable the whole feature (`syncWaves.enabled: false`).

Default wave assignment, with gaps of 10 for user-injected resources:

```text
ServiceAccount / RBAC          -30
SecretStore                    -20
ExternalSecret / ConfigMap     -10
Service / ImageUpdater           0
StatefulSet                     10
Deployment                      20
HPA / VPA / PDB / ScaledObject /
  ServiceMonitor / PodMonitor   21
NetworkPolicy / ReferenceGrant  25
Ingress / HTTPRoute /
  GRPCRoute / TLSRoute          30
```

Rationale for the order:

- SA / RBAC at the back so workloads have an identity to run as.
- SecretStore before ExternalSecret (ExternalSecret references it).
- ExternalSecret and ConfigMap before workloads (env / volume mounts depend on them).
- Service before workloads' ports actually resolve (small but real win for ServiceMonitor at +21).
- StatefulSet before Deployment is mostly cosmetic — they don't depend on each other — but having a fixed order keeps Argo CD's "applying wave 10/wave 20" output stable across releases.
- Derived resources (HPA, VPA, PDB, ScaledObject, monitors) at +21, immediately after the workload they reference.
- NetworkPolicy / ReferenceGrant at +25 — they reference Services and workloads.
- Ingress / Gateway API routes at +30, last — they reference Services that need to exist.

`jobGroups` opts out of the chart-level default. Job hooks declare their own waves at `jobGroups.<g>.hooks.argocd.syncWave` (or per job), because hook ordering is a per-job decision (a migration runs at -10, a smoke check runs at +10) and a chart-wide default would be wrong for at least half of cases.

## Consequences

**What this enables:**

- Clean first-time syncs in Argo CD: each wave finishes Healthy before the next starts. No false "Degraded" flicker on a fresh install.
- Users who don't run Argo CD pay nothing — the annotations are inert outside Argo CD.
- Per-resource override: `integrations.argocd.syncWaves.ingress: 50` if you want Ingress especially late.
- Per-resource opt-out: `integrations.argocd.syncWaves.serviceMonitor: null` to omit that one annotation, useful when a different controller manages monitor objects.

**What it costs:**

- The defaults are opinionated. Teams that already use sync waves with their own conventions will need to override the whole map.
- The annotation is added to every resource the chart emits, even in non-Argo-CD environments. It's harmless, but a few bytes per object in `kubectl get … -o yaml`.
- Adding a new resource kind to the chart requires adding it to `syncWaves` with a sensible number — not just a template change.

## Override examples

```yaml
# Disable the feature entirely
integrations:
  argocd:
    syncWaves:
      enabled: false

# Push Ingress later (after a custom CRD applied at +35)
integrations:
  argocd:
    syncWaves:
      ingress: 40

# Drop the annotation only for ServiceMonitor (a controller writes its own)
integrations:
  argocd:
    syncWaves:
      serviceMonitor: null
```

## Alternatives considered

- **No defaults; users set waves themselves.** Rejected: the common case (a fresh install) flickers Degraded for no good reason. Most users will never set waves; the chart should give them the right answer for free.
- **Helm `post-install` / `post-upgrade` hooks instead.** Rejected: chart-wide hook annotations on workloads are heavyweight and break Argo CD's incremental sync model.
- **Hard-code the waves; no override.** Rejected: closes the door on teams with existing conventions.

## References

- `values.yaml` — the `integrations.argocd.syncWaves` block.
- `templates/_annotations.tpl` — `uhc.metadataAnnotations` (composes the wave annotation), `uhc.syncWaveAnnotation` (resolves the per-kind value).
- All resource templates — each calls `uhc.metadataAnnotations` for its kind.
- Argo CD docs: <https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/>.
- Related: [ADR 005](005-jobgroups-unification.md) (job hook waves), [ADR 006](006-integrations-namespace.md).
