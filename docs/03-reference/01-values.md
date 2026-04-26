# Values reference

The authoritative per-field source is the heavily-annotated [`values.yaml`](../../values.yaml) at the chart root. This page complements it with two things `values.yaml` comments don't aggregate:

- a **topical index** of every top-level key, grouped by feature, with cross-links to the relevant ADR and example folder;
- a **cross-cutting rules cheatsheet** for behaviours that span multiple keys (env merge, label precedence, port ordering, jobGroups merge, autoscaler exclusion, chart-owned vs external resolution).

For the schema's machine-checkable shape, see [`02-schema.md`](02-schema.md). For supported Kubernetes / CRD versions, see [`03-compatibility.md`](03-compatibility.md).

## Topical index

| Topic | Top-level keys | Read more |
|-------|----------------|-----------|
| Identity & metadata | `commonLabels`, `commonAnnotations`, `labels.standard`, `nameOverride`, `fullnameOverride` | [ADR 011](../05-adr/011-standard-wins-labels-and-invariant-selectors.md) |
| Environment & config | `global.env`, `env`, `envSecrets`, `envConfigMaps`, `configMaps`, `podAnnotations`, `jobPodAnnotations` | [ADR 003](../05-adr/003-layered-inheritance-and-override.md) · [ADR 015](../05-adr/015-eso-data-vs-datafrom.md) |
| Image & pulls | `image`, `imagePullSecrets`, `jobCompletionImage` | [`02-examples/01-minimal/`](../02-examples/01-minimal/) |
| Deployments / StatefulSets | `deployments`, `statefulSets`, `strategy`, `statefulSetUpdateStrategy`, `revisionHistoryLimit`, `progressDeadlineSeconds`, `minReadySeconds` | [ADR 002](../05-adr/002-multi-workload-keyed-maps.md) · [`02-examples/03-statefulset-pvc/`](../02-examples/03-statefulset-pvc/) |
| Per-pod containers | per-workload `initContainers`, `sidecars` | [ADR 002](../05-adr/002-multi-workload-keyed-maps.md) · [ADR 014](../05-adr/014-deterministic-ordering.md) · [`02-examples/10-init-containers/`](../02-examples/10-init-containers/) |
| Job groups | `jobGroups` | [ADR 005](../05-adr/005-jobgroups-unification.md) · [ADR 012](../05-adr/012-job-spec-hashing-for-idempotency.md) · [`02-examples/05-cronjobs/`](../02-examples/05-cronjobs/) |
| Networking — Ingress | `ingress`, `ingresses` | [ADR 009](../05-adr/009-dual-networking-stack.md) · [`02-examples/02-web-app-ingress/`](../02-examples/02-web-app-ingress/) |
| Networking — Gateway API | `httpRoute`, `httpRoutes`, `grpcRoute`, `grpcRoutes`, `tlsRoute`, `tlsRoutes`, `referenceGrant`, `referenceGrants` | [ADR 009](../05-adr/009-dual-networking-stack.md) · [`02-examples/04-gateway-api/`](../02-examples/04-gateway-api/) |
| Autoscaling | per-workload `hpa`, `keda`, `verticalPodAutoscaler` | [ADR 007](../05-adr/007-autoscaler-mutual-exclusion.md) · [`02-examples/08-keda-event-driven/`](../02-examples/08-keda-event-driven/) |
| Monitoring | `integrations.monitoring.defaults`, per-workload `metrics`, auto-exposed metrics port | [ADR 008](../05-adr/008-multi-provider-monitoring.md) · [ADR 016](../05-adr/016-metrics-port-auto-exposure.md) · [`02-examples/06-monitoring/`](../02-examples/06-monitoring/) |
| Secrets (ESO) | `integrations.eso.enabled`, `integrations.eso.secretStores`, `integrations.eso.externalSecrets` | [ADR 015](../05-adr/015-eso-data-vs-datafrom.md) · [`02-examples/07-external-secrets/`](../02-examples/07-external-secrets/) |
| Identity & RBAC | `serviceAccount`, `rbac`, `automountServiceAccountToken` | [`02-examples/07-external-secrets/`](../02-examples/07-external-secrets/) |
| Pod-level policies | `podSecurityContext`, `securityContext`, `terminationGracePeriodSeconds`, `podDisruptionBudget`, `topologySpreadConstraints`, `priorityClassName`, `nodeSelector`, `affinity`, `tolerations`, `hostAliases` | — |
| Volumes | `volumes`, `volumeMounts` (root-level maps; per-workload override) | [ADR 004](../05-adr/004-maps-over-lists.md) |
| Argo CD integrations | `integrations.argocd.syncWaves`, `integrations.argocd.imageUpdater` | [ADR 010](../05-adr/010-argocd-sync-waves.md) |
| Stakater Reloader | `integrations.stakater.reloader` | [ADR 017](../05-adr/017-reloader-annotation-injection.md) |

Every entry resolves to its full annotated definition in [`values.yaml`](../../values.yaml) — search by key.

## Cross-cutting rules

The behaviours below span multiple keys; reading the `values.yaml` comment on any single one doesn't tell you the whole story.

### Environment variable merge order

For each container, env is composed in this order (later layers win on key collision; non-colliding keys union):

```
NAMESPACE (fieldRef)  →  global.env  →  env  →  workload.env  →  container.env
```

Per-workload opt-out via `deployments.<name>.inherit.env.{global,root}: false`. See [ADR 003](../05-adr/003-layered-inheritance-and-override.md).

### Label precedence on workload resources

- `app.kubernetes.io/name` and `app.kubernetes.io/instance` are **always** emitted on workload selectors and pod template labels, regardless of any toggle. The Kubernetes API forbids selector mutation; the chart guarantees they're present.
- `commonLabels` cannot shadow chart-managed `app.kubernetes.io/*` keys — chart values silently win.
- `labels.standard.{partOf,version,managedBy,enabled}` toggles affect singletons (ServiceAccount, Ingress, Routes, etc.) but not workload selectors.

See [ADR 011](../05-adr/011-standard-wins-labels-and-invariant-selectors.md).

### Port ordering inside Service / pod template

When a workload's `service.ports` (or per-container `ports`) is iterated:

```
http (if present)  →  others alphabetically  →  metrics (if present)
```

Auto-injected metrics port (from `integrations.monitoring.defaults.exposeService`) lands last. See [ADR 014](../05-adr/014-deterministic-ordering.md) and [ADR 016](../05-adr/016-metrics-port-auto-exposure.md).

### `jobGroups` group → job merge

For each per-job field:

- **maps** (env, podAnnotations, metadataAnnotations) — replace per key; later wins.
- **lists** (envSecrets, envConfigMaps, tolerations) — concat.
- **volumes / volumeMounts** — replace by name (a volume can't be partially `emptyDir` and partially `configMap`).

`hashSuffix: true` together with a delete-policy that removes the Job after success is rejected fail-fast — the Job would re-run on every sync. See [ADR 005](../05-adr/005-jobgroups-unification.md) and [ADR 012](../05-adr/012-job-spec-hashing-for-idempotency.md).

### Autoscaler mutual exclusion

- `hpa.enabled: true` and `keda.enabled: true` on the same workload is fail-fast. Both manage `spec.replicas`; both running is undefined behaviour.
- `verticalPodAutoscaler` is orthogonal to both (touches `resources.requests`, not `replicas`).
- When any HPA-class scaler is on, `spec.replicas` is omitted from the rendered manifest so Helm doesn't bounce the count on every apply.

See [ADR 007](../05-adr/007-autoscaler-mutual-exclusion.md).

### Init containers and sidecars share one container shape

`deployments.<name>.initContainers` and `deployments.<name>.sidecars` (same under `statefulSets.<name>`) are maps keyed by container name. Both flow through the same renderer as the main container: `image`, `command`/`args`, `env`, `envSecrets`, `volumeMounts`, `resources`, `securityContext`, `lifecycle`. Both inherit the parent workload's `inherit.env` / `inherit.configMaps` / `inherit.configMapMount` flags. Neither inherits root-level `volumeMounts.<containerName>` — declare local mounts inline. Render order is `sortAlpha`; for `initContainers` Kubernetes runs them sequentially in declared order, so prefix names with `01-`, `02-`, … when run order matters (same convention as `jobGroups[*].tasks`). Reloader does not re-trigger init containers — they run only on Pod creation, so a config change rolls the workload and a fresh init pass runs.

### Chart-owned vs external name resolution

When the same name appears in both a chart-owned map (`configMaps`, `integrations.eso.externalSecrets`) and an external reference list (`envConfigMaps`, `envSecrets`):

- chart-owned wins: the rendered reference points at `<release-fullname>-<name>`.
- external is silently shadowed.
- having both with the same name is a smell — pick distinct names.

See [ADR 015](../05-adr/015-eso-data-vs-datafrom.md).

## Where to go next

- Concrete configurations to copy → [`02-examples/`](../02-examples/).
- Why a specific shape was chosen → [`05-adr/`](../05-adr/).
- IDE-side schema validation → [`02-schema.md`](02-schema.md).
- Cluster / CRD requirements → [`03-compatibility.md`](03-compatibility.md).
