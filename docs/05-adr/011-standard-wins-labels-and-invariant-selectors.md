# 011 — Standard-wins labels and invariant workload selectors

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

Two label requirements apply to every Kubernetes workload:

1. **`spec.selector.matchLabels`** must match a subset of `spec.template.metadata.labels`. The selector is **immutable** for Deployment / StatefulSet / Job. Mutating it is rejected by the API server. Drift here breaks upgrades.
2. **Cluster policies** (Kyverno / OPA-Gatekeeper / built-in admission) increasingly require labels like `app.kubernetes.io/name`, `app.kubernetes.io/instance`, plus organisation-specific ones like `cost-center`, `team`, `environment`.

Two label *sources* converge on each resource the chart renders:

- **Chart-managed labels** — the `app.kubernetes.io/*` set the chart computes (`name`, `instance`, `version`, `managed-by`, `part-of`, `component`).
- **User-supplied labels** — `commonLabels` plus per-feature annotation/label customisation under `integrations.<name>.customize.labels`.

Without explicit rules, two failure modes are easy to hit:

- A user setting `commonLabels.app.kubernetes.io/instance: my-thing` overrides the chart's selector instance label, and now the Deployment's selector points at pods that don't exist.
- A label-policy admission flag (`labels.standard.enabled: false`) intended to suppress noisy `app.kubernetes.io/version` on singleton resources accidentally suppresses the selector labels too — pods orphaned.

## Decision

**Two rules, applied uniformly:**

### Rule 1: Standard-wins on `app.kubernetes.io/*`

When `commonLabels` (or any per-feature label customisation) declares a key in the `app.kubernetes.io/*` namespace that the chart also computes, the **chart's value wins**. The user's value is silently dropped.

Implementation: `templates/_helpers.tpl:uhc.labels` — chart labels come *last* in the merge, so they overwrite. Documented next to the `commonLabels` / `commonAnnotations` / `labels.standard` blocks in `values.yaml`.

### Rule 2: Invariant selectors on workloads

Workload resources — Deployment, StatefulSet, Service, Job, CronJob (its Job template), HPA, VPA, PDB, ScaledObject, ServiceMonitor, PodMonitor, ESO `ExternalSecret`'s target metadata — **always** emit `app.kubernetes.io/name` and `app.kubernetes.io/instance` in `spec.selector.matchLabels` (and matching pod template labels), regardless of any toggle.

The `labels.standard.*` toggles (`enabled`, `name`, `instance`, `version`, `managedBy`, `partOf`) only apply to **singleton resources** — ServiceAccount, Ingress, *Routes, ReferenceGrant, NetworkPolicy, ImageUpdater, RBAC, top-level ConfigMap. On workloads, `name` and `instance` are forced on; the other three (`partOf`, `version`, `managedBy`) follow their toggles.

Implementation: `templates/_helpers.tpl:uhc.workloadSelectorLabels` always emits `name` + `instance`, called from every workload template's `spec.selector.matchLabels` and pod template `metadata.labels`.

## Consequences

**What this enables:**

- Users can set fleet-wide `commonLabels` (e.g. `cost-center: data-platform`) without ever risking selector breakage.
- A cluster with a strict label-policy admission can disable noisy standard labels on singletons (`labels.standard.enabled: false`) without breaking workloads.
- The chart's selector contract is a single sentence: "name and instance are always there, everything else is configurable."

**What it costs:**

- Users who genuinely want to override `app.kubernetes.io/instance` (typical in clusters with weird Helm release naming conventions) must use `nameOverride` / `fullnameOverride` instead. The chart documents this.
- The "standard-wins" rule is a silent suppression — users may set a value and not see it in the rendered manifest. We accept this in exchange for the safety guarantee. The schema cannot help here (it doesn't know which keys collide).

## Examples

```yaml
commonLabels:
  cost-center: data-platform
  app.kubernetes.io/instance: not-this-one    # silently dropped — chart's value wins

labels:
  standard:
    enabled: true       # singletons emit standard labels
    version: false      # but suppress app.kubernetes.io/version everywhere
    managedBy: false    # and app.kubernetes.io/managed-by
```

Effective on a Deployment workload:

- `app.kubernetes.io/name: <chart name>` — always (selector invariant)
- `app.kubernetes.io/instance: <release-fullname>-<workload>` — always (selector invariant)
- `app.kubernetes.io/part-of: <chart name>` — yes (`partOf` defaults true)
- `app.kubernetes.io/version: …` — **no** (toggle off)
- `app.kubernetes.io/managed-by: …` — **no** (toggle off)
- `cost-center: data-platform` — yes
- `app.kubernetes.io/instance: not-this-one` — **dropped** (collides with selector)

## Alternatives considered

- **User-wins on label collisions.** Rejected: lets users break selectors silently. The whole reason selectors are immutable in Kubernetes is that recovery is expensive.
- **Fail loudly on collision.** Rejected: a `helm template` failure on what is almost always a copy-paste mistake is too brittle. Silent override with documentation is the right trade.
- **Move selectors to a separate, locked-down structure invisible to `commonLabels`.** Rejected: the chart already uses standard `app.kubernetes.io/*` keys. Inventing parallel keys would break consumer tooling that expects them.
- **Allow toggle-off of selector labels on workloads.** Rejected: the API server would reject the resource. A failing render is better than a confusing apply error, but a working render with the labels in is better still.

## References

- `values.yaml` — narrative for the `commonLabels`, `commonAnnotations` and `labels.standard.*` blocks at the top of the file.
- `templates/_helpers.tpl` — `uhc.labels`, `uhc.workloadLabels`, `uhc.workloadSelectorLabels`.
- Tests: `tests/integrations_test.yaml`, `tests/fixtures/commonlabels-conflict.yaml`.
- Related: [ADR 006](006-integrations-namespace.md).
