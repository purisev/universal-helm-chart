# Values Reference

All top-level values keys, grouped by concern. For detailed examples see the linked documentation pages.

---

## Global / image

| Key | Type | Default | Description |
|---|---|---|---|
| `global.env` | map | `{}` | Env vars injected into all containers (layer 2 of 4) |
| `global.application.env` | map | — | Env vars from global application config (layer 1 of 4) |
| `image.repository` | string | `""` | Default container image repository |
| `image.tag` | string | `""` | Default container image tag |
| `image.pullPolicy` | string | `IfNotPresent` | `Always` \| `IfNotPresent` \| `Never` |
| `imagePullSecrets` | list | `[]` | Image pull secrets for all pods |
| `nameOverride` | string | `""` | Override chart name component of `fullname` |
| `fullnameOverride` | string | `""` | Override the full release name used in resource names |

---

## Environment layers

| Key | Type | Default | Description |
|---|---|---|---|
| `envDev.enabled` | bool | `false` | Enable dev-specific env vars |
| `envDev.env` | map | `{}` | Dev env vars (layer 3 of 4) |
| `envProd.enabled` | bool | `false` | Enable prod-specific env vars |
| `envProd.env` | map | `{}` | Prod env vars (layer 3 of 4) |
| `envSecrets` | list | `[]` | Secrets injected via `envFrom.secretRef` into all containers |
| `envConfigMaps` | list | `[]` | ConfigMaps injected via `envFrom.configMapRef` into all containers |

See [Environment Variables](environment-variables.md) for full details.

---

## Workload maps

| Key | Type | Description |
|---|---|---|
| `deployments` | map | Deployment workloads; each key → Deployment + Service |
| `statefulSets` | map | StatefulSet workloads; each key → StatefulSet + headless Service |
| `cronJobs` | map | CronJob workloads; each key → CronJob |

See [Workloads](workloads.md) for full field reference.

---

## Pod defaults

| Key | Type | Default | Description |
|---|---|---|---|
| `podAnnotations` | map | `{}` | Annotations on all pod templates (including Jobs) |
| `jobPodAnnotations` | map | `{}` | Annotations on Job/CronJob pod templates only (merged with `podAnnotations`) |
| `podSecurityContext.runAsNonRoot` | bool | `true` | |
| `podSecurityContext.runAsUser` | int | `1000` | |
| `podSecurityContext.runAsGroup` | int | `1000` | |
| `podSecurityContext.fsGroup` | int | `1000` | |
| `podSecurityContext.seccompProfile.type` | string | `RuntimeDefault` | |
| `securityContext.allowPrivilegeEscalation` | bool | `false` | |
| `securityContext.readOnlyRootFilesystem` | bool | `true` | |
| `securityContext.capabilities.drop` | list | `["ALL"]` | |
| `automountServiceAccountToken` | bool | `false` | |
| `terminationGracePeriodSeconds` | int | `30` | |
| `minReadySeconds` | int | `0` | |
| `revisionHistoryLimit` | int | `10` | |
| `progressDeadlineSeconds` | int | `600` | Deployments only |

---

## Update strategy

| Key | Type | Default | Description |
|---|---|---|---|
| `strategy.type` | string | `RollingUpdate` | Deployment update strategy |
| `strategy.rollingUpdate.maxSurge` | int\|string | `1` | |
| `strategy.rollingUpdate.maxUnavailable` | int\|string | `0` | |
| `statefulSetUpdateStrategy.type` | string | `RollingUpdate` | StatefulSet update strategy |
| `statefulSetUpdateStrategy.rollingUpdate.partition` | int | `0` | Partition-based rolling update |

---

## Scheduling

| Key | Type | Default | Description |
|---|---|---|---|
| `nodeSelector` | map | `{}` | Applied to all workloads |
| `affinity` | map | `{}` | Default affinity; overridable per workload |
| `tolerations` | list | `[]` | Default tolerations; merged with per-workload |
| `hostAliases` | list | `[]` | Injected into all pods; disable per-workload with `inheritRootHostAliases: false` |
| `priorityClassName` | string | `""` | Default priority class |
| `topologySpreadConstraints.enabled` | bool | `false` | Disabled by default (avoid failures on single-node clusters) |
| `topologySpreadConstraints.constraints` | list | zone + hostname | TSC rules |
| `syncWaves.databaseJobsSyncWave` | string | `"2"` | ArgoCD sync wave for dbJob |
| `syncWaves.jobsSyncWave` | string | `"3"` | ArgoCD sync wave for initJob |
| `syncWaves.deploymentSyncWave` | string | `"10"` | ArgoCD sync wave for workloads |

---

## Storage / volumes

| Key | Type | Default | Description |
|---|---|---|---|
| `volumes` | list | `[]` | Extra volumes for all pods |
| `volumeMounts` | map | `{}` | Volume mounts keyed by workload name (`volumeMounts.web`, `volumeMounts.initJob`, `volumeMounts.dbJob`) |
| `configMaps` | map | `{}` | Chart-level ConfigMaps; optional `mountPath` triggers auto-mount |

See [Secrets & Config](secrets-and-config.md) for ConfigMap details.

---

## Ingress / Gateway API

| Key | Type | Default | Description |
|---|---|---|---|
| `ingress.enabled` | bool | `false` | Singleton Ingress |
| `ingress.ingressClassName` | string | `""` | |
| `ingress.annotations` | map | `{}` | |
| `ingress.hosts` | list | `[]` | |
| `ingress.tls` | list | `[]` | |
| `ingresses` | map | `{}` | Multi-ingress map; each key → `Ingress/<fullname>-<key>` |
| `httpRoute.enabled` | bool | `false` | Singleton HTTPRoute (also rendered if any workload has `httpRoute.enabled: true`) |
| `httpRoute.parentRefs` | list | `[]` | Gateway references (inherited by per-workload merge) |
| `httpRoute.hostnames` | list | `[]` | Hostnames (inherited by per-workload merge) |
| `httpRoute.rules` | list | `[]` | Root-level rules (rendered before workload rules) |
| `httpRoute.annotations` | map | `{}` | |
| `httpRoutes` | map | `{}` | Multi-HTTPRoute map; each key → `HTTPRoute/<fullname>-<key>` |
| `grpcRoute.*` | — | — | Same structure as `httpRoute`; default port 50051 |
| `grpcRoutes` | map | `{}` | |
| `tlsRoute.*` | — | — | Same structure; `hostnames` required; no matches/filters |
| `tlsRoutes` | map | `{}` | |
| `referenceGrant.enabled` | bool | `false` | Singleton ReferenceGrant |
| `referenceGrant.from` | list | `[]` | Allowed sources (`group`, `kind`, `namespace`) |
| `referenceGrant.to` | list | `[]` | Target resource types (`group`, `kind`, optional `name`) |
| `referenceGrants` | map | `{}` | Multi-ReferenceGrant map |

See [Ingress & Gateway API](ingress-and-gateway.md) for full details.

---

## ArgoCD lifecycle jobs

| Key | Type | Default | Description |
|---|---|---|---|
| `dbJob.enabled` | bool | `false` | Database migration job (wave 2) |
| `dbJob.image` | object | — | Separate image for migration container |
| `dbJob.backoffLimit` | int | `3` | |
| `dbJob.activeDeadlineSeconds` | int\|null | `null` | |
| `dbJob.ttlSecondsAfterFinished` | int | `3600` | |
| `dbJob.tasks` | map | `{}` | initContainer tasks (alphabetical order) |
| `dbJob.completionImage` | string | `alpine:3.21` | |
| `initJob.enabled` | bool | `false` | Init job (wave 3); uses root image |
| `initJob.backoffLimit` | int | `3` | |
| `initJob.tasks` | map | `{}` | |
| `postSync.enabled` | bool | `false` | PostSync hook jobs |
| `postSync.syncWave` | string | `"0"` | |
| `postSync.backoffLimit` | int | `1` | |
| `postSync.hookDeletePolicy` | string | `HookSucceeded` | |
| `postSync.jobs` | map | `{}` | Each key → separate Job |

See [ArgoCD Integration](argocd-integration.md) for full details.

---

## Autoscaling / availability

| Key | Type | Default | Description |
|---|---|---|---|
| `verticalPodAutoscaler.enabled` | bool | `false` | Global VPA; overridable per workload |
| `verticalPodAutoscaler.updateMode` | string | `Initial` | `Off` \| `Initial` \| `Recreate` \| `InPlaceOrRecreate` |
| `verticalPodAutoscaler.resourcePolicy` | object | — | Container policies |
| `podDisruptionBudget.enabled` | bool | `false` | Global PDB; overridable per workload |
| `podDisruptionBudget.minAvailable` | int\|string | `1` | |
| `reloader.enabled` | bool | `true` | Stakater Reloader annotation on Deployments/StatefulSets |

See [Autoscaling](autoscaling.md) for full details.

---

## Secrets / external

| Key | Type | Description |
|---|---|---|
| `secretStores` | map | ESO SecretStore / ClusterSecretStore resources |
| `externalSecrets` | map | ESO ExternalSecret resources |

See [Secrets & Config](secrets-and-config.md) for full details.

---

## Identity / access

| Key | Type | Default | Description |
|---|---|---|---|
| `serviceAccount.create` | bool | `false` | Create a ServiceAccount |
| `serviceAccount.name` | string | `""` | Override name; defaults to chart fullname |
| `serviceAccount.annotations` | map | `{}` | e.g. IRSA role ARN, Workload Identity annotation |
| `rbac.enabled` | bool | `false` | Create Role + RoleBinding (requires `serviceAccount.create: true`) |
| `rbac.rules` | list | `[]` | RBAC policy rules |

---

## Image automation

| Key | Type | Default | Description |
|---|---|---|---|
| `imageUpdater.enabled` | bool | `false` | Create an ArgoCD ImageUpdater CR |
| `imageUpdater.namespace` | string | `""` | Namespace for the CR (typically `argocd`) |
| `imageUpdater.appNamePattern` | string | `""` | ArgoCD Application name pattern (shorthand mode) |
| `imageUpdater.commonUpdateSettings` | object | `{}` | Shared update settings (shorthand mode) |
| `imageUpdater.writeBackConfig` | object | `{}` | Write-back config (shorthand mode) |
| `imageUpdater.images` | list | `[]` | Images to track (shorthand mode) |
| `imageUpdater.applicationRefs` | list | `[]` | Full applicationRefs (manual mode; overrides shorthand fields) |

See [ArgoCD Integration](argocd-integration.md) for full details.
