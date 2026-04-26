# 012 — Pod-spec hashing for Job idempotency under GitOps

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

Jobs in GitOps look easy until you ask: when should a Job re-run?

- Argo CD / Flux apply manifests on every sync — sometimes once a minute. A Job named `<release>-migrate` already exists; the controller sees the manifest unchanged and does nothing. That's correct *if* the migration's intent has not changed.
- The team bumps the migrator's image tag from `v1` to `v2`. The manifest changes. But the Job resource's `spec` is largely immutable — Kubernetes rejects `kubectl apply` updates to a Job spec. Argo CD reports the Application as `OutOfSync` forever.
- The team works around it with `argocd.argoproj.io/hook: PreSync` + `hook-delete-policy: HookSucceeded`. Now the Job is recreated on every sync, even when nothing changed. Migrations re-run. Idempotency is on the migration script, not the chart.

The clean solution is to make the Job's **name** a function of its **spec**. If the spec changes, the name changes — Argo CD sees a new resource and applies it; the old Job is garbage-collected via `ttlSecondsAfterFinished`. If the spec doesn't change, neither does the name — sync is a no-op.

## Decision

Each `jobGroups.<g>.jobs.<j>` entry produces a Kubernetes Job (or CronJob) named:

```text
<release-fullname>-<group[:8]>-<job>-<sha8>
```

where `sha8` is the first 8 hex characters of `sha256` over a deterministic JSON serialisation of the rendered Job/CronJob `spec`. Computed by `templates/_helpers.tpl:uhc.jobGroupHash`.

**What's included in the hash:**

- `image.repository`, `image.tag`, `image.pullPolicy`
- `command`, `args`, `tasks` (full structure, including each task's command/args/image)
- effective `env` (after the four-layer merge of [ADR 003](003-layered-inheritance-and-override.md))
- `envFrom` (resolved `envSecrets` + `envConfigMaps`)
- `volumes`, `volumeMounts`
- `resources`
- `securityContext`, `podSecurityContext`
- `nodeSelector`, `affinity`, `tolerations`, `topologySpreadConstraints`
- `serviceAccountName`
- `restartPolicy`, `backoffLimit`, `activeDeadlineSeconds`
- `ttlSecondsAfterFinished`
- `podAnnotations` (effective merge) — **included by default**, opt out with `hashIncludePodAnnotations: false`

**What's excluded:**

- `metadataAnnotations` (chart-managed annotations: sync waves, Reloader, etc. — they shouldn't trigger re-runs)
- `hooks.argocd.*`, `hooks.helm.*` (changing the hook annotation alone shouldn't re-run the Job)
- `ttlSecondsAfterFinished` *change alone* doesn't matter operationally — included for completeness

**Opt-out toggles per group:**

- `hashSuffix: false` — disable hashing entirely; resource name is `<release>-<group>-<job>` and Job re-creation is the user's problem.
- `hashIncludePodAnnotations: false` — keep hashing on, but exclude `podAnnotations` from the hash (useful when a mutating webhook adds annotations post-render — Vault, Datadog).

**Fail-fast guard.** A configuration with `hashSuffix: true` together with a delete policy that removes the Job after success (`hooks.argocd.deletePolicy: HookSucceeded` or `hooks.helm.deletePolicy: hook-succeeded`) is rejected. Reason: every successful run would delete the Job, the next sync would recreate it under the same name (hash unchanged), and the migration would run on every sync — defeating the whole point of hashing.

## Consequences

**What this enables:**

- A migration runs **once** per spec change. Argo CD on a 1-minute sync interval is harmless.
- Image bump (`v1` → `v2`) creates a new Job; the old one's lifecycle (success / cleanup) is handled via `ttlSecondsAfterFinished`.
- Mutating annotations injected by an admission controller (Vault inject) participate in the hash — a new Vault role rotation triggers a re-run, which is usually what the team wants. Opt out via `hashIncludePodAnnotations: false` when it isn't.

**What it costs:**

- **Mutable image tags break idempotency.** If `image.tag` is `dev` and a new image is pushed under the same tag, the rendered string is unchanged → hash is unchanged → no re-run, even though the binary changed. Workarounds documented in `values.yaml:595–622`:
  1. Argo CD Image Updater with `update-strategy: digest` — rewrites `image.tag` to `dev@sha256:…`. The digest enters the hash.
  2. Immutable tags (semver, git-sha) — every release is its own tag; the hash naturally changes.
  3. Opt out of idempotency on the affected groups (`hashSuffix: false` + `BeforeHookCreation` delete policy). Job runs every sync.
- Old Jobs accumulate in the cluster until `ttlSecondsAfterFinished` triggers GC. The chart defaults this to 1h; users with churny migrations can tune it.
- The hash is computed in Go template — see `uhc.jobGroupHash` for the full algorithm. Stable: any change to the algorithm is a chart breaking change because every group's Job names would shift, recreating every Job in flight.

## Worked example

```yaml
jobGroups:
  db:
    image: { repository: my/migrator, tag: v1 }
    jobs:
      migrate:
        command: ./migrate.sh
```

Renders Job `myrelease-db-migrate-3f9a1b2c`. Bump tag to `v2`: Job becomes `myrelease-db-migrate-7c4d8e1f`. Argo CD applies the new Job; `ttlSecondsAfterFinished` cleans up `…-3f9a1b2c` an hour after it succeeded.

## Alternatives considered

- **Use Helm hooks (`pre-install,pre-upgrade`) with `hook-delete-policy: hook-succeeded`.** Rejected: re-runs every Helm sync regardless of whether anything changed. Idempotency falls on the migration script.
- **Use Argo CD `Sync` hook + `Replace=true`.** Rejected: same problem, plus tighter coupling to Argo CD specifically.
- **Hash the entire rendered manifest, not just the spec.** Rejected: includes annotations like `argocd.argoproj.io/sync-wave` whose changes shouldn't re-run the Job.
- **Per-job `idempotencyKey: …` user-provided.** Rejected: pushes the burden onto the user. The whole point is to make this automatic.

## References

- `values.yaml:575–622` — narrative on Job idempotency, mutable tags, recommended setups
- `values.yaml:668–669` — `hashSuffix` and `hashIncludePodAnnotations` toggles
- `templates/_helpers.tpl` — `uhc.jobGroupHash`, `uhc.jobGroupSpec` (assembles the spec input)
- `templates/job-groups.yaml`, `templates/cronjob-groups.yaml` — fail-fast guard
- Tests: `tests/job_groups_test.yaml`, `tests/cronjob_groups_test.yaml`
- Related: [ADR 005](005-jobgroups-unification.md)
