# 05 — jobGroups (Job + CronJob)

Two `jobGroups` in one release:

- `migrations` — `kind: Job`, runs as a `PreSync` hook on every Argo CD sync. Tasks-mode: two ordered initContainers (`01-structure` then `02-seed`) inside one Job.
- `nightly` — `kind: CronJob` with two scheduled jobs sharing image and env: `cleanup` at 02:00 UTC and `report` at 06:00 UTC.

## What this shows

- Group-level config (`image`, `envSecrets`, `hooks`) cascades into every job in `jobs:`. Per-job fields override.
- **Tasks mode**: a job whose work is split across multiple ordered initContainers, then a tiny "completed" container marks the Job successful. Useful for migration → seed pipelines where step ordering matters. Kubernetes runs `initContainers` sequentially in their declared order, and the chart emits the `tasks` map sorted alphabetically — so when ordering matters, prefix task names with `01-`, `02-`, `03-` etc. to make the run order explicit. (See [ADR 014](../../05-adr/014-deterministic-ordering.md).)
- Single-container mode (`command` / `args` directly on the job) for the CronJob members.
- **Hash-suffixed Job names** (`<release>-migrations-schema-<sha8>`) — the Job re-runs only when its rendered spec changes (image bump, env change, command edit). Argo CD on a 1-minute sync interval is harmless. ([ADR 012](../../05-adr/012-job-spec-hashing-for-idempotency.md))
- Argo CD hook annotations on the migrations group → Argo CD treats those Jobs as PreSync hooks; the user-visible workloads continue applying once the hook completes.
- CronJob fields (`schedule`, `timeZone`, `concurrencyPolicy`, history limits) live per job — different schedules per job in the same group.

## Delta from `01-minimal`

| Added | What |
|-------|------|
| `jobGroups.migrations` | Pre-sync schema migration via tasks-mode initContainers. |
| `jobGroups.nightly` | Two CronJobs sharing image/env, different schedules. |
| Argo CD hooks | Migrations group runs as `PreSync` with `syncWave: -2`. |
| External Secret reference | `db-credentials` Secret carries `DB_PASSWORD` for migrations. |

(There is no Deployment in this example — purely batch workloads.)

## Files

| File | Purpose |
|------|---------|
| [`values.yaml`](values.yaml) | Chart values. |
| [`argocd/application.yaml`](argocd/application.yaml) | Argo CD `Application`, single source. |
| [`argocd/application-multisource.yaml`](argocd/application-multisource.yaml) | Argo CD `Application` with `spec.sources[]`. |
| [`flux/ocirepository.yaml`](flux/ocirepository.yaml) | Flux `OCIRepository`. |
| [`flux/helmrelease.yaml`](flux/helmrelease.yaml) | Flux `HelmRelease`. |
| [`helm/install.sh`](helm/install.sh) | Plain `helm upgrade --install`. |

## Try it

```bash
# Pre-create the credentials Secret
kubectl create namespace batch
kubectl create secret generic db-credentials \
  --from-literal=DB_PASSWORD='changeme' \
  -n batch

bash helm/install.sh
```

## Related ADRs

- [ADR 005 — `jobGroups` unification](../../05-adr/005-jobgroups-unification.md)
- [ADR 012 — Pod-spec hashing for Job idempotency](../../05-adr/012-job-spec-hashing-for-idempotency.md)
- [ADR 010 — Argo CD sync-waves](../../05-adr/010-argocd-sync-waves.md)
