# 10 — init containers

A Deployment with two init containers that run **before** the main `nginx` container starts. The first blocks pod startup until the database is reachable; the second applies a schema migration. Both run sequentially, in the order their map keys sort alphabetically.

## What this shows

- Per-workload `initContainers` declared as a map keyed by container name.
- The `01-`, `02-` prefix convention for run order — same idea as `jobGroups[*].tasks` (Kubernetes runs init containers sequentially in declared order; the chart sorts the map alphabetically before emitting).
- Per-init container `image` override (the migration init uses a different image from the main container).
- `envSecrets` on an init container — root `envSecrets` are merged in automatically; the per-init list adds workload-specific Secrets on top.

## Delta vs. previous examples

`01-minimal/` shows the simplest case: one container, one Service. This example adds two init containers ahead of the main container without changing anything else. The same `initContainers` map is also accepted under `statefulSets.<name>` with identical semantics.

## Files

| File | Purpose |
|------|---------|
| [`values.yaml`](values.yaml) | Chart values for this scenario. |
| [`argocd/application.yaml`](argocd/application.yaml) | Argo CD `Application`, single source. |
| [`argocd/application-multisource.yaml`](argocd/application-multisource.yaml) | Argo CD `Application` with `spec.sources[]` — chart from OCI, values from a git repo via `$values`. |
| [`flux/ocirepository.yaml`](flux/ocirepository.yaml) | Flux `OCIRepository` pointing at the OCI chart. |
| [`flux/helmrelease.yaml`](flux/helmrelease.yaml) | Flux `HelmRelease` consuming the `OCIRepository`. |
| [`helm/install.sh`](helm/install.sh) | Plain `helm upgrade --install` command. |

## Try it

Pick any one of:

- **Helm CLI:** `bash helm/install.sh`
- **Argo CD:** `kubectl apply -f argocd/application.yaml -n argocd`
- **Flux:** `kubectl apply -f flux/`

## Heads-up

- **Reloader does not re-run init containers on config changes.** Init containers run only on Pod creation. When a watched ConfigMap or Secret changes, Reloader rolls the workload — a fresh Pod starts, and the init containers run again as part of that fresh start. If your migration is idempotent (and it should be), this is exactly what you want.
- **`volumeMounts.<initContainerName>` at root level is NOT inherited.** Init containers behave like sidecars here — declare any mounts they need inline under `deployments.<name>.initContainers.<initName>.volumeMounts`. Auto-mounted ConfigMaps (those declared under `configMaps.<name>` with a `mountPath`) DO mount into init containers, unless disabled via `inherit.configMapMount`.
