# 017 — Reloader annotation injection

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

[Stakater Reloader](https://github.com/stakater/Reloader) is a small Kubernetes controller that watches ConfigMaps and Secrets, and triggers a rolling restart of any Deployment / StatefulSet that mounts a changed one. Activation is by annotation on the workload:

- `reloader.stakater.com/auto: "true"` — auto-discover all referenced ConfigMaps / Secrets, restart on change.
- `reloader.stakater.com/match: "true"` plus `reloader.stakater.com/search-cm-only: "true"` (or `*-secret-only`) — narrow the discovery.

The chart already manages every ConfigMap and Secret a workload references. Asking users to also annotate the workload by hand is mechanical busywork that's easy to forget when adding the second ConfigMap.

A second concern is **ExternalSecret targets**: ESO-managed Secrets are written by the controller, not by Helm. Annotating the ExternalSecret directly does nothing — Reloader watches the resulting K8s Secret. ESO does propagate `spec.target.template.metadata.annotations` onto the generated Secret, so the right place to land the Reloader annotation is on the ExternalSecret's target template.

## Decision

A single switch at `integrations.stakater.reloader.enabled: true` injects the Reloader annotation onto the right resources.

**Where the annotation lands:**

- `Deployment.metadata.annotations`
- `StatefulSet.metadata.annotations`
- `ConfigMap.metadata.annotations` (chart-owned ConfigMaps from `.Values.configMaps`)
- `ExternalSecret.spec.target.template.metadata.annotations` — ESO copies these onto the generated Secret, so Reloader sees the change.

**What annotation lands:**

- When `integrations.stakater.reloader.annotations` is empty (the default), the chart applies the single annotation `reloader.stakater.com/auto` with value `"true"`.
- When `integrations.stakater.reloader.annotations` is non-empty, that map **fully replaces** the default. There is no merge. This is intentional — Reloader's annotation set is mutually exclusive (`auto` vs `match`-based discovery; `cm-only` vs `secret-only`) and a partial merge would produce confusing combinations.

## Consequences

**What this enables:**

- One toggle wires Reloader into every workload + ConfigMap + ESO-managed Secret in the release.
- Switching from auto-discovery to match-strategy is a one-block change in `values.yaml`:
  ```yaml
  integrations:
    stakater:
      reloader:
        enabled: true
        annotations:
          reloader.stakater.com/match: "true"
          reloader.stakater.com/search-cm-only: "true"
  ```
- Workloads consuming ESO-managed Secrets get rolling restarts on remote-secret rotation without any extra configuration.

**What it costs:**

- The "no merge with user annotations" rule is unusual elsewhere in the chart (most other annotation sets do merge with user-supplied entries). Documented next to the `integrations.stakater.reloader` block in `values.yaml`. The choice keeps Reloader's strategy unambiguous.
- The annotation is not added to Job / CronJob templates — Reloader doesn't restart Jobs (they're one-shot), and re-creating a finished Job to "pick up" a Secret change isn't useful. Job recreation is governed by the spec hash ([ADR 012](012-job-spec-hashing-for-idempotency.md)) instead.
- Reloader must be installed in the cluster. The chart doesn't check; if the controller isn't there, the annotation is inert.

## Default behaviour

Off by default (`enabled: false`). Reloader is a useful but optional integration; releases that don't need restart-on-config-change pay nothing for it.

## Alternatives considered

- **Merge user-supplied annotations with the `auto: "true"` default.** Rejected: Reloader's discovery strategies are mutually exclusive; a merge produces undefined behaviour.
- **Annotate only Deployment / StatefulSet, leave ConfigMap and ExternalSecret untouched.** Rejected: ConfigMap annotation is a Reloader convenience for resources it might otherwise overlook (e.g. CMs only mounted as volumes); ESO target template annotation is required for ESO-managed Secrets. Skipping either leaves a hole.
- **Per-workload Reloader toggle.** Rejected: in practice teams either want Reloader-driven restarts everywhere in a release or nowhere. A per-workload knob doubles the surface for a vanishingly small fraction of use cases.

## References

- `values.yaml` — the `integrations.stakater.reloader` block.
- `templates/_helpers.tpl` — `uhc.reloaderAnnotations`.
- `templates/deployment.yaml`, `templates/statefulset.yaml`, `templates/configmap.yaml`, `templates/externalsecret.yaml` — annotation injection sites.
- Stakater Reloader: <https://github.com/stakater/Reloader>.
- Related: [ADR 006](006-integrations-namespace.md), [ADR 012](012-job-spec-hashing-for-idempotency.md).
