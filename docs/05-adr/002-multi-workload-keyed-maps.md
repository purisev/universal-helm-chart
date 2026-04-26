# 002 — Multi-workload via keyed maps in a single release

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

A single release routinely needs more than one workload of the same kind: an API and a worker, a web app and an admin app, a primary StatefulSet and a read-replica StatefulSet. The chart's universal scope ([ADR 001](001-universal-chart-scope.md)) requires us to express these without template duplication or per-workload subcharts.

Helm gives us two natural shapes in `values.yaml`: a **list** of objects (each carrying a `name`) or a **map** keyed by name. Both can drive a `range` loop. They differ on how downstream operators read them, how they merge with overlay values, and how easily a human spots a duplicate.

## Decision

Workloads of the same kind are declared as **keyed maps** in `values.yaml`. The map key is the workload's logical name and becomes part of the rendered Kubernetes resource name (`<release-fullname>-<key>`). The chart iterates each map with `keys ... | sortAlpha` so the rendered output is deterministic.

The three workload maps are:

- `deployments` — one Deployment + Service per key.
- `statefulSets` — one StatefulSet + headless Service per key.
- `jobGroups` — one Job-or-CronJob *group* per key. See [ADR 005](005-jobgroups-unification.md).

The same shape is applied to per-workload sub-collections (e.g. `service.ports`, `volumes`, `volumeMounts`, `sidecars`, `initContainers`) — see [ADR 004](004-maps-over-lists.md) for the broader rule.

## Consequences

**What this enables:**

- **Uniqueness by construction.** YAML maps cannot have duplicate keys, so two workloads cannot accidentally share a name within one values file.
- **Targeted overrides** in overlay values: setting `deployments.api.replicaCount: 3` in a per-environment overlay leaves the rest of `deployments.api` and all of `deployments.worker` untouched — Helm's `merge` is map-aware. With a list, an overlay would replace the entire list.
- **Stable resource ordering** across renders, because the chart sorts keys alphabetically before iterating. Diffs in Argo CD / `helm diff` stay small and meaningful.
- **Per-workload disabling** via the conventional `deployments.<name>.enabled: false`, without touching neighbouring workloads.

**What it costs:**

- The map key must be a valid DNS-1123 subdomain segment (it lands in resource names). The schema enforces this; users cannot put arbitrary characters in the key.
- "Insertion order" cannot be expressed. When ordering matters (rule precedence in HTTP routes, sidecar startup order), we either fall back to a list (Gateway API rules) or expose an explicit `priority` field — see [ADR 014](014-deterministic-ordering.md).
- The single map iteration model means every workload of a given kind is rendered from one template file. The template must be careful to use `$workload` scope rather than `.` when reaching back into `$.Values`.

## Alternatives considered

- **List of objects with `name:`.** Rejected: duplicates silently allowed, overlay merging replaces the whole list, no targeted override.
- **Subchart per workload.** Rejected: heavyweight, breaks `global.env` propagation across "siblings", and Argo CD multi-source flow becomes awkward.
- **A separate chart per workload kind, composed by a parent chart.** Rejected for the same reasons as in [ADR 001](001-universal-chart-scope.md): drift and review burden.

## References

- `values.yaml` — the `jobGroups`, `deployments` and `statefulSets` top-level blocks.
- `templates/deployment.yaml`, `templates/statefulset.yaml`, `templates/job-groups.yaml`, `templates/cronjob-groups.yaml` — all iterate via `range $name, $cfg := .Values.<map>` after `keys ... | sortAlpha`.
- Related: [ADR 004](004-maps-over-lists.md), [ADR 014](014-deterministic-ordering.md).
