# 019 — Pre-fill API-server defaults on atomic list fields

- **Status:** Accepted
- **Date:** 2026-08-19

## Context

Argo CD synced with `syncOptions: [ServerSideApply=true]` reported a handful of this chart's resources as permanently `OutOfSync`, even immediately after a clean sync with no pending git change: `StatefulSet.spec.volumeClaimTemplates`, and every Gateway API route kind's `spec.parentRefs` / `spec.rules[].backendRefs` (`HTTPRoute`, `GRPCRoute`, `TLSRoute`).

Reproduced directly against a kind cluster: the Kubernetes API server (or, for Gateway API, the CRD's own OpenAPI schema defaults) fills in fields on these objects that the chart never rendered — `apiVersion: v1`, `kind: PersistentVolumeClaim`, `spec.volumeMode: Filesystem`, and `status: {phase: Pending}` on each `volumeClaimTemplates` entry; `group`/`kind` on `parentRefs` and `backendRefs` entries; `weight: 1` on `backendRefs`; `matches[].method.type: Exact` on `GRPCRoute` matches left unset.

None of this is a bug in the objects themselves — Kubernetes is allowed to default fields the client didn't set. The problem is specific to how these fields are *shaped*: each one lives inside a list field with no merge key (`x-kubernetes-list-type: atomic`, or no strategic-merge-patch directive at all for core `volumeClaimTemplates`). Struct-shaped fields we partially specify (e.g. `ExternalSecret.spec.target`, which gets `deletionPolicy` and `template.engineVersion` defaulted) merge key-by-key under both classic apply and Server-Side Apply, so an unmentioned sibling field is simply left alone. List entries without a merge key don't get that courtesy: once a field manager owns the list, it owns it *as a whole unit*, and any element field present live but absent from the desired manifest reads as a pending patch back to the (shorter) desired version — forever `OutOfSync`, because the server immediately re-adds the same defaults on the next reconcile.

This only surfaces under `ServerSideApply=true`. Argo CD's default (client-side) apply path doesn't flag it — its diff has more lenient handling of fields it never took ownership of. `ServerSideApply=true` is a common Argo CD recommendation, though, so charts that skip this only work by accident for users on the default sync strategy.

## Decision

Where the chart renders an atomic-list field whose element shape includes fields we know the server (or CRD schema) will default, **pre-fill those exact defaults in the template**, using a plain-key-wins merge (`merge (deepCopy $userValue) $defaults`) so any value the user *did* set is untouched:

- `templates/statefulset.yaml` — each `volumeClaimTemplates` entry gets `apiVersion: v1`, `kind: PersistentVolumeClaim`, `spec.volumeMode: Filesystem` (default), `status: {phase: Pending}`.
- `templates/_gateway.tpl` — `uhc.gatewayParentRefs` fills `group: gateway.networking.k8s.io`, `kind: Gateway` on every `parentRefs` entry; `uhc.gatewayBackendRefs` fills `group: ""`, `kind: Service`, `weight: 1` on every `backendRefs` entry (both helpers, used by `HTTPRoute`, `GRPCRoute`, `TLSRoute`, root and per-workload and plural-map render sites alike). `uhc.grpcRouteRuleSpec` additionally fills `matches[].method.type: Exact` when a `method` match is set without one.

Desired now equals live byte-for-byte on these fields, so the diff Argo CD would otherwise (re-)compute under Server-Side Apply is empty regardless of sync strategy.

## Consequences

**What this enables:**

- No `ignoreDifferences` required for `volumeClaimTemplates` / Gateway API routes, on any Argo CD sync strategy (client-side or `ServerSideApply=true`).
- The fix is invisible to users who never look at the rendered YAML — user-supplied field values always win via the merge, only genuinely-omitted fields get filled.

**What it costs:**

- The rendered manifests carry a few more explicit fields (`apiVersion`, `kind`, `status: {phase: Pending}` inside `volumeClaimTemplates`; `group`/`kind`/`weight` on route refs) that most hand-written manifests leave implicit. `status:` inside a spec-embedded `PersistentVolumeClaim` template reads unusually at first glance — it's real, structurally valid content (`StatefulSetSpec.VolumeClaimTemplates` is typed `[]PersistentVolumeClaim`, `status` included), not a mistake.
- If a future Kubernetes/Gateway API release changes what gets defaulted (e.g. a new `PersistentVolumeClaim` default field, or Gateway API adding a field to `parentRefs`), this list of pre-filled defaults needs a matching update, or the diff reappears for that one new field. Confirmed only for the fields listed above — other Gateway API match-level defaults (e.g. `HTTPRoute` `matches[].path.type`) follow the identical pattern but weren't hit by the values used to reproduce this, so aren't pre-filled yet.
- Only fixes fields shaped as unmerged lists. A struct field the server defaults (like `ExternalSecret.spec.target.deletionPolicy`) was already fine and needed no change; a chart bug that under-specifies a *new* unmerged-list field in the future will need the same treatment, not this one applied blindly everywhere.

## Alternatives considered

- **Document `ignoreDifferences` for affected users instead of changing chart output.** Rejected as the primary fix: it pushes a per-consumer Argo CD config burden onto everyone who happens to use `ServerSideApply=true`, for a gap the chart can close for free. Still valid as a fallback for any future unmerged-list default this ADR's list doesn't yet cover.
- **Switch affected CRD list fields to a merge-key strategy chart-side.** Not possible — `x-kubernetes-list-type`/patch strategy is defined by the upstream API (core Kubernetes types, Gateway API CRDs), not something a chart consuming those types can override.
- **Recommend users avoid `ServerSideApply=true`.** Rejected: it's a reasonable, commonly-recommended Argo CD setting for unrelated reasons (large manifests, multi-controller field ownership); the chart shouldn't have an opinion on it.

## References

- `templates/statefulset.yaml`, `templates/_gateway.tpl` — the fix.
- `templates/externalsecret.yaml` — an example of a struct field (`spec.target`) that needed no change, for contrast.
- Related: [ADR 010](010-argocd-sync-waves.md) (other Argo CD-specific chart behavior).
