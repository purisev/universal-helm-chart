# 021 — Optional single-workload naming

- **Status:** Accepted
- **Date:** 2026-09-07

## Context

The chart names every per-workload resource `<fullname>-<workloadName>` and
puts the workload key in `app.kubernetes.io/name`, with the full construction
in `app.kubernetes.io/instance`. That suffix is what lets several workloads
share one release without colliding (see
[ADR 002](002-multi-workload-keyed-maps.md)).

Plenty of releases run a single workload. There the suffix buys nothing and
costs something: `myrel-payments-api` where the service is already called
`payments`, DNS names longer than they need to be, and a mismatch with the
per-service charts teams migrate away from, whose Service was simply
`<release>`. Callers that hardcode a Service DNS name have to be edited as
part of the migration, which is exactly the friction the universal chart is
supposed to remove.

## Decision

`naming.omitWorkloadSuffix` (default `false`) builds every per-workload
resource name from `<fullname>` alone. All names route through one helper,
`uhc.workloadResourceName`, so the flag reaches Deployment, StatefulSet,
Service, HPA, ScaledObject, VPA, PDB, NetworkPolicy, ServiceMonitor,
PodMonitor and the workload ConfigMap, including the `-headless`, `-metrics`
and `-config` variants. Labels and selectors follow through
`uhc.workloadLabels` / `uhc.workloadSelectorLabels`: `app.kubernetes.io/name`
becomes the chart name and `app.kubernetes.io/instance` becomes `<fullname>`,
the pair the chart already emits on its singleton resources.

With more than one enabled entry across `deployments` and `statefulSets`,
`helm template` fails and names the offenders. Silently keeping the suffix
would make the flag mean different things in different releases, and honoring
it would render several workloads under one set of names.

Container names keep the workload key, and `jobGroups` names are untouched:
both are addressed by key rather than by release identity.

## Consequences

- Off by default, and the rendered output with it off is byte-identical to
  before, so no existing release moves.
- Flipping it on an existing release renames the workload and changes an
  immutable selector, so the Deployment or StatefulSet is replaced rather than
  updated. It is an install-time decision.
- With the suffix gone, a workload resource and the release ServiceAccount
  share a name. Different kinds, so Kubernetes accepts it.
- Adding a second workload to a release that uses the flag fails the render
  until the flag is turned off. The error says so.

## Alternatives considered

- **Fall back to suffixed names when a release grows past one workload.** The
  same values would produce different names depending on how many workloads
  are defined, and adding a workload would silently rename the first one.
- **Derive it automatically from a single-workload release.** Same problem
  without even an opt-in to point at.
- **Leave labels and selectors suffixed and rename objects only.** Cheaper to
  toggle, but it leaves `app.kubernetes.io/name: api` on a release that no
  longer names anything `api`.

## References

- `naming.omitWorkloadSuffix` in `values.yaml`.
- Helpers `uhc.omitWorkloadSuffix`, `uhc.workloadResourceName` in
  `templates/_labels.tpl`.
- [ADR 002](002-multi-workload-keyed-maps.md),
  [ADR 011](011-standard-wins-labels-and-invariant-selectors.md).
