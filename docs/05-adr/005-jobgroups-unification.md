# 005 — `jobGroups` unifying Job and CronJob

- **Status:** Accepted (replaces previous separate `jobs` / `cronJobs` blocks)
- **Date:** 2025-04-25

## Context

Database migrations, scheduled cleanup tasks, ad-hoc backfills and smoke checks share most of their configuration: the same image, the same env, the same secrets, the same scheduling parameters. What they differ on is mostly the trigger — a Job runs once on deploy; a CronJob runs on a schedule.

Before 2.0.0 the chart had separate `jobs:` and `cronJobs:` top-level blocks. The duplication produced two bad outcomes:

1. Real-world groups of related jobs (a migrate Job and a seed Job that both want the same image, env vars and volumes) had to repeat all the shared fields. Eventually one of the copies drifted.
2. The "Job vs CronJob" decision is sometimes made late — e.g. a smoke check starts as a Job and becomes a periodic check. Moving across the boundary required manual edits in two places.

Tasks-mode (multiple sequenced steps in one Job using initContainers) added another twist: a single logical "thing the team runs" became a *group* of related jobs sharing context.

## Decision

Unify under a single top-level map: `jobGroups`. Each group has:

- a `kind` field — `Job` or `CronJob` (set on the **group**, not per-job; mixed-kind groups are deliberately not supported);
- shared configuration — image, env, envSecrets, envConfigMaps, hooks, volumes, volumeMounts, tolerations, security context, resources, etc.;
- a nested `jobs:` map where each entry becomes one Job/CronJob resource and may override any group-level field.

The merge between group and per-job is one level deeper than the layer cascade in [ADR 003](003-layered-inheritance-and-override.md), and the rules are field-shape specific:

| Field shape | Examples | Merge rule |
|-------------|----------|------------|
| Atomic / replace-whole | `backoffLimit`, `schedule`, `restartPolicy`, `command` (string-or-array), `args`, `tasks` (whole map), `ttlSecondsAfterFinished`, `concurrencyPolicy` | Job value wins when set; otherwise the group value (and otherwise nothing). Composite values like `command` and `tasks` are treated as opaque — the job's value replaces the group's wholesale, no recursion |
| List | `envSecrets`, `envConfigMaps`, `tolerations` | Concat group entries first, then job entries |
| Nested map | `env`, `image`, `securityContext`, `podSecurityContext`, `resources`, `nodeSelector`, `affinity`, `inherit`, `metadataAnnotations`, `hooks.argocd`, `hooks.helm` | **Deep-merge**: keys present in the job replace the group's value at that key, keys present only on the group are preserved |
| Name-keyed map | `volumes`, `volumeMounts` | Per-entry replace by name: a job's `volumes.data` replaces the group's `volumes.data` whole; non-colliding keys from both layers coexist. The chart does **not** deep-merge into a single volume/mount because k8s volume kinds are mutually exclusive (a name is either `emptyDir` or `configMap`, never both) |
| `kind` | `Job` / `CronJob` | Group only — per-job override is intentionally rejected |
| `podAnnotations` | — | Effective merge of root → root.jobPodAnnotations → group → job (last wins) |

This is implemented in `templates/_jobs.tpl:uhc.jobGroupSpec` and documented in the worked example next to the `jobGroups` block in `values.yaml`.

Resource name: `<release-fullname>-<group[:8]>-<job>[-<sha8>]`. The `sha8` suffix is governed by [ADR 012](012-job-spec-hashing-for-idempotency.md).

`tasks` (a map of initContainers) is mutually exclusive with single-container mode (`command` / `args`). The schema enforces this — a job with both is rejected.

**Task naming convention.** Kubernetes runs `initContainers` **sequentially in the order they appear in `spec.initContainers[]`**. The chart sorts the `tasks` map alphabetically before emitting (see [ADR 014](014-deterministic-ordering.md)), so **the alphabetical order of task names is the order in which they actually run**. When the order matters, prefix task names with `01-`, `02-`, `03-` etc. — that's the convention used in the worked example below and in [`02-examples/05-cronjobs/`](../02-examples/05-cronjobs/).

## Consequences

**What this enables:**

- A migration job and a seed job declared as siblings under one group share image, env, volumes — with concise, override-only difference at the per-job level.
- A logical task crossing the Job ↔ CronJob boundary is a one-line edit (`kind:`).
- The hash-suffix idempotency model ([ADR 012](012-job-spec-hashing-for-idempotency.md)) operates uniformly on both kinds.
- Argo CD / Helm hook annotations (`hooks.argocd.*`, `hooks.helm.*`) live on the group with per-job override — natural for "all jobs in this group are pre-install hooks".

**What it costs:**

- Mixed Job + CronJob in one group is rejected. Users with such a need declare two groups. In practice this is a non-issue: a migration Job and a nightly cleanup CronJob have nothing in common worth sharing.
- Per-job `kind` overrides are not allowed. Same rationale.
- Tasks mode and single-container mode are mutually exclusive — schema-enforced. A user wanting both must split into two jobs.
- The merge code (`uhc.jobGroupSpec`) is the most complex helper in the chart. It is covered by `tests/job_groups_test.yaml` and `tests/cronjob_groups_test.yaml`, which together hold the largest single-suite test count in the repo.

## Examples

```yaml
jobGroups:
  db:
    kind: Job
    image:
      repository: my/migrator
      tag: v1
    env:
      LOG_LEVEL:
        value: info
    envSecrets:
      - db-creds
    hooks:
      argocd:
        hook: PreSync
        syncWave: "-2"
    jobs:
      migrate:
        # tasks-mode: each task becomes an initContainer.
        # Tasks run in the alphabetical order of their map keys — prefix names
        # with 01-, 02-, ... when ordering matters (Kubernetes runs initContainers
        # sequentially).
        tasks:
          01-schema:
            command: |
              psql -c "CREATE TABLE IF NOT EXISTS ..."
          02-seed:
            args:
              - seed
              - --rows=100
      smoke-check:
        # single-container mode: one shot
        command: wget -q -O- http://api/health || exit 1
        backoffLimit: 1
        hooks:
          argocd:
            syncWave: "3"   # overrides group default
  nightly:
    kind: CronJob
    image:
      repository: my/cleaner
      tag: v1
    jobs:
      cleanup:
        schedule: "0 2 * * *"
        timeZone: UTC
        concurrencyPolicy: Forbid
```

## Alternatives considered

- **Two top-level blocks `jobs` and `cronJobs`.** Rejected: the pre-2.0.0 status quo. Encouraged drift between sibling jobs and made Job→CronJob conversion painful.
- **Per-job `kind` field.** Rejected: a CronJob and a Job in the same group share almost nothing operationally (hooks differ, schedule semantics differ, completion behaviour differs). Worth the inconvenience to keep groups homogeneous.
- **Flatten — every Job/CronJob is its own top-level entry.** Rejected: would re-introduce the duplication that motivated grouping.

## References

- `values.yaml` — the `jobGroups` block (narrative + worked example).
- `templates/_jobs.tpl` — `uhc.jobGroupSpec`, `uhc.jobGroupHash`, `uhc.jobGroupHookAnnotations`.
- `templates/job-groups.yaml`, `templates/cronjob-groups.yaml`.
- Tests: `tests/job_groups_test.yaml`, `tests/cronjob_groups_test.yaml`.
- Related: [ADR 003](003-layered-inheritance-and-override.md), [ADR 012](012-job-spec-hashing-for-idempotency.md).
