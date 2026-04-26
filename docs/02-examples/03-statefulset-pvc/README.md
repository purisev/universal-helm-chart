# 03 — StatefulSet with PVC and headless Service

A 3-replica PostgreSQL-style StatefulSet with stable storage and stable network identity. The headless Service exposes each pod under a predictable DNS name (`<release>-db-0.<release>-db.<ns>.svc`).

## What this shows

- A `statefulSets.db` workload — replaces `deployments.<n>` for ordered, stateful pods.
- `volumeClaimTemplates.data` — every pod gets its own PVC, retained across restarts and scale-up.
- `service.clusterIP: None` — headless Service required by StatefulSet for stable per-pod DNS.
- `replicaCount: 3` with `podManagementPolicy: OrderedReady` (chart default).
- `envSecrets` referencing an externally-managed Secret for `POSTGRES_PASSWORD` (no ESO here — see `07-external-secrets/` for that).
- Per-pod `volumeMounts` map keyed by mount name, referencing the `volumeClaimTemplates` entry by name.

## Delta from `02-web-app-ingress`

| Changed | What and why |
|---------|--------------|
| `deployments` → `statefulSets` | StatefulSet, not Deployment — needed for stable storage + stable DNS. |
| `volumeClaimTemplates` | Per-pod PVC; `volumes` (the per-pod ephemeral kind) wouldn't survive pod replacement. |
| `service.clusterIP: None` | Headless Service so each pod gets `<pod>.<service>.<ns>.svc` DNS. |
| `service.ports.postgres` | Single non-`http` port — port ordering rule still puts it first since "http" is absent (alphabetical fallback). |
| No Ingress, no HPA | Stateful workloads aren't horizontally autoscaled in this template (use a connection pooler or read-replicas pattern instead). |
| Pre-existing Secret | `db-credentials` Secret must exist in the namespace before install (or come from a different release). For an ESO-managed flow, see [`../07-external-secrets/`](../07-external-secrets/). |

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
# First create the password Secret (this example doesn't manage it)
kubectl create namespace stateful
kubectl create secret generic db-credentials \
  --from-literal=POSTGRES_PASSWORD='changeme' \
  --from-literal=POSTGRES_USER='app' \
  -n stateful

# Then install via any of these
bash helm/install.sh
kubectl apply -f argocd/application.yaml -n argocd
kubectl apply -f flux/
```

## Prerequisites

- A default StorageClass in the cluster, or override `volumeClaimTemplates.data.storageClassName` for your provisioner.
- The `db-credentials` Secret pre-existing in the target namespace.
