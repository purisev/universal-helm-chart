# Values reference

`values.yaml` at the chart root carries machine-readable defaults only — no inline comments. This page is the annotated reference: a topical index of every top-level key grouped by feature, with cross-links to the relevant ADR and example folder, plus a cross-cutting rules cheatsheet for behaviours that span multiple keys.

For the schema's machine-checkable shape, see [`02-schema.md`](02-schema.md). For supported Kubernetes / CRD versions, see [`03-compatibility.md`](03-compatibility.md). For a complete working example with every chart feature enabled (passes `helm template`), see [`values.yaml.example`](../../values.yaml.example) at the chart root.

## Topical index

| Topic | Top-level keys | Read more |
|-------|----------------|-----------|
| Identity & metadata | `commonLabels`, `commonAnnotations`, `labels.standard`, `nameOverride`, `fullnameOverride` | [ADR 011](../05-adr/011-standard-wins-labels-and-invariant-selectors.md) |
| Environment & config | `global.env`, `env`, `envSecrets`, `envConfigMaps`, `configMaps`, `podAnnotations`, `jobPodAnnotations` | [ADR 003](../05-adr/003-layered-inheritance-and-override.md) · [ADR 015](../05-adr/015-eso-data-vs-datafrom.md) |
| Image & pulls | `image`, `imagePullSecrets`, `jobCompletionImage` | [`02-examples/01-minimal/`](../02-examples/01-minimal/) |
| Deployments / StatefulSets | `deployments`, `statefulSets`, `strategy`, `statefulSetUpdateStrategy`, `revisionHistoryLimit`, `progressDeadlineSeconds`, `minReadySeconds` | [ADR 002](../05-adr/002-multi-workload-keyed-maps.md) · [`02-examples/03-statefulset-pvc/`](../02-examples/03-statefulset-pvc/) |
| Per-pod containers | per-workload `initContainers`, `sidecars` | [ADR 002](../05-adr/002-multi-workload-keyed-maps.md) · [ADR 014](../05-adr/014-deterministic-ordering.md) · [`02-examples/10-init-containers/`](../02-examples/10-init-containers/) |
| Job groups | `jobGroups` | [ADR 005](../05-adr/005-jobgroups-unification.md) · [ADR 012](../05-adr/012-job-spec-hashing-for-idempotency.md) · [`02-examples/05-cronjobs/`](../02-examples/05-cronjobs/) |
| Networking — Ingress | `ingress` (`hosts`, `tls` as native k8s list, `defaultBackend`), `ingresses` | [ADR 009](../05-adr/009-dual-networking-stack.md) · [`02-examples/02-web-app-ingress/`](../02-examples/02-web-app-ingress/) |
| Networking — Gateway API | `httpRoute`, `httpRoutes`, `grpcRoute`, `grpcRoutes`, `tlsRoute`, `tlsRoutes`, `referenceGrant`, `referenceGrants` | [ADR 009](../05-adr/009-dual-networking-stack.md) · [`02-examples/04-gateway-api/`](../02-examples/04-gateway-api/) |
| Autoscaling | per-workload `hpa`, `keda`, `verticalPodAutoscaler` | [ADR 007](../05-adr/007-autoscaler-mutual-exclusion.md) · [`02-examples/08-keda-event-driven/`](../02-examples/08-keda-event-driven/) |
| Monitoring | `integrations.monitoring.defaults`, per-workload `metrics`, auto-exposed metrics port | [ADR 008](../05-adr/008-multi-provider-monitoring.md) · [ADR 016](../05-adr/016-metrics-port-auto-exposure.md) · [`02-examples/06-monitoring/`](../02-examples/06-monitoring/) |
| Secrets (ESO) | `integrations.eso.enabled`, `integrations.eso.secretStores`, `integrations.eso.externalSecrets` | [ADR 015](../05-adr/015-eso-data-vs-datafrom.md) · [`02-examples/07-external-secrets/`](../02-examples/07-external-secrets/) |
| Identity & RBAC | `serviceAccount` (`create` defaults to `true`), `rbac` (`enabled`, `clusterScoped`, `rules`), `automountServiceAccountToken` | [`02-examples/07-external-secrets/`](../02-examples/07-external-secrets/) |
| Pod-level policies | `podSecurityContext`, `securityContext`, `resources` (root-level defaults: `cpu: 10m`, `memory: 32Mi`), `terminationGracePeriodSeconds`, `podDisruptionBudget`, `topologySpreadConstraints` (native k8s list), `priorityClassName`, `nodeSelector`, `affinity`, `tolerations`, `hostAliases` | — |
| Volumes | `volumes`, `volumeMounts` (root-level maps; per-workload override) | [ADR 004](../05-adr/004-maps-over-lists.md) |
| Argo CD integrations | `integrations.argocd.syncWaves`, `integrations.argocd.imageUpdater` | [ADR 010](../05-adr/010-argocd-sync-waves.md) |
| Stakater Reloader | `integrations.stakater.reloader` | [ADR 017](../05-adr/017-reloader-annotation-injection.md) |

For a working configuration in each area, follow the example links above. For the full value shape, see [`values.schema.json`](../../values.schema.json).

## Cross-cutting rules

The behaviours below span multiple keys; reading the `values.yaml` comment on any single one doesn't tell you the whole story.

### Environment variable merge order

For each container, env is composed in this order (later layers win on key collision; non-colliding keys union):

```
NAMESPACE (fieldRef)  →  global.env  →  env  →  workload.env  →  container.env
```

Per-workload opt-out: `inherit.env.{global,root}: false` (skip env layers), `inherit.envSecrets: false` (exclude root `envSecrets` from `envFrom`), `inherit.configMaps: false` (skip root `envConfigMaps`). See [ADR 003](../05-adr/003-layered-inheritance-and-override.md).

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

### HTTPRoute rule fields (`name`, `timeouts`, `retry`, `sessionPersistence`)

Every HTTPRoute rule (in `httpRoute.rules`, `httpRoutes.<n>.rules`, and per-workload `deployments.<w>.httpRoute.rules` / `statefulSets.<w>.httpRoute.rules`) accepts four optional field groups beyond `matches`, `filters`, and `backendRefs`:

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` (`SectionName`: lowercase RFC 1123 label, optionally dotted, max 253 chars) | Identifies the rule. Surfaced in Gateway API status conditions, access logs, and distributed traces. MUST be unique within the route. |
| `timeouts.request` | `string` (Gateway API Duration, [GEP-2257](https://gateway-api.sigs.k8s.io/geps/gep-2257/)) | Total time budget for the complete HTTP request/response cycle, measured from when the gateway forwards the request. `"0s"` disables the timeout. Example: `"30s"`. |
| `timeouts.backendRequest` | `string` (Gateway API Duration) | Time budget for the backend to process the request. Must be ≤ `timeouts.request`. Example: `"10s"`. |
| `retry.attempts` | `integer (≥ 0)` | Maximum number of retry attempts. |
| `retry.codes` | `array of integer (400–599)` | HTTP status codes that trigger a retry (e.g. `[503, 504]`). Implementations MUST support 500/502/503/504 as retriable. |
| `retry.backoff` | `string` (Gateway API Duration) | Minimum wait between retry attempts. Example: `"1s"`. |
| `sessionPersistence.sessionName` | `string` (1–128 chars) | Identifier the implementation uses for the persistence value (cookie name or header name, depending on `type`). |
| `sessionPersistence.type` | `enum`: `Cookie` \| `Header` | Persistence mechanism. Defaults to `Cookie` server-side when omitted. |
| `sessionPersistence.absoluteTimeout` | `string` (Gateway API Duration) | Maximum lifetime of the session, regardless of activity. Example: `"1h"`. |
| `sessionPersistence.idleTimeout` | `string` (Gateway API Duration) | Maximum idle time before the session expires. Example: `"10m"`. |
| `sessionPersistence.cookieConfig.lifetimeType` | `enum`: `Permanent` \| `Session` | Cookie lifetime style (relevant only when `type: Cookie`). |

All four field groups are optional and independently combinable — you can set `timeouts` without `retry`, or `name` without either. Fields absent from a rule are omitted from the rendered manifest; they do not inherit from sibling rules or the route root.

> **Schema strictness.** Each rule entry is validated against a strict schema (`additionalProperties: false`) listing only the fields above plus `matches`, `filters`, `backendRefs`, `serviceName`, and `servicePort`. Unknown keys (typos, deprecated fields, or Gateway API fields not yet wired into the chart) fail at `helm template` time with a clear validation error rather than being silently dropped. If you depend on a Gateway API HTTPRouteRule field not in this list, open an issue or submit a PR — see [ADR 009](../05-adr/009-dual-networking-stack.md).

#### Gateway API channel and version requirements

The chart's CRD-channel detection runs at template time when `gateway.networking.k8s.io/v1` is present in `Capabilities.APIVersions` and emits a fail-fast error if the field's required CRD channel is missing. Detection is skipped when rendering offline (`helm template` without `--api-versions`).

| Field | Minimum Gateway API | Channel | Detection marker |
|-------|---------------------|---------|------------------|
| `name` | v1.4.0 (Standard) **or** v1.2.0+ (Experimental) | Standard since v1.4.0; Experimental from v1.2 to v1.3 | `gateway.networking.k8s.io/v1/BackendTLSPolicy` (Standard, graduated in v1.4.0) **or** `gateway.networking.k8s.io/v1alpha2/TCPRoute` (Experimental) |
| `timeouts.*` | v1.2.0 | Standard | none — implied by `gateway.networking.k8s.io/v1` |
| `retry.*` | v1.2.0 | **Experimental only** (still Experimental as of v1.5.1) | `gateway.networking.k8s.io/v1alpha2/TCPRoute` (Experimental) |
| `sessionPersistence.*` | v1.2.0 | **Experimental only** (still Experimental as of v1.5.1) | `gateway.networking.k8s.io/v1alpha2/TCPRoute` (Experimental) |

If your cluster runs **Standard** channel CRDs older than v1.4 and you need `name`, you must install the Experimental channel; if you need `retry` or `sessionPersistence` at all, you must install the Experimental channel — Standard CRDs reject those fields.

See the [`04-gateway-api` example](../02-examples/04-gateway-api/) for a working configuration and Gateway API's [release channels](https://gateway-api.sigs.k8s.io/concepts/versioning/#release-channels) for installation guidance.

### GRPCRoute rule fields (`name`, `sessionPersistence`)

Every GRPCRoute rule (in `grpcRoute.rules`, `grpcRoutes.<n>.rules`, and per-workload `deployments.<w>.grpcRoute.rules` / `statefulSets.<w>.grpcRoute.rules`) accepts two optional field groups beyond `matches`, `filters`, and `backendRefs`:

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` (`SectionName`: lowercase RFC 1123 label, optionally dotted, max 253 chars) | Identifies the rule. Surfaced in Gateway API status conditions and traces. MUST be unique within the route. |
| `sessionPersistence.sessionName` | `string` (1–128 chars) | Identifier the implementation uses for the persistence value (cookie name or header name, depending on `type`). |
| `sessionPersistence.type` | `enum`: `Cookie` \| `Header` | Persistence mechanism. Defaults to `Cookie` server-side when omitted. |
| `sessionPersistence.absoluteTimeout` | `string` (Gateway API Duration) | Maximum lifetime of the session, regardless of activity. Example: `"1h"`. |
| `sessionPersistence.idleTimeout` | `string` (Gateway API Duration) | Maximum idle time before the session expires. Example: `"10m"`. |
| `sessionPersistence.cookieConfig.lifetimeType` | `enum`: `Permanent` \| `Session` | Cookie lifetime style (relevant only when `type: Cookie`). |

Both groups are independently optional. **GRPCRouteRule has no `timeouts` or `retry`** — those are HTTPRoute-only fields in the Gateway API spec.

> **Schema strictness.** Each rule entry is validated against a strict schema (`additionalProperties: false`) listing only `name`, `matches`, `filters`, `backendRefs`, `serviceName`, `servicePort`, and `sessionPersistence`. Unknown keys fail at `helm template` time.

#### Gateway API channel and version requirements

| Field | Minimum Gateway API | Channel | Detection marker |
|-------|---------------------|---------|------------------|
| `name` | v1.4.0 (Standard) **or** v1.2.0+ (Experimental) | Standard since v1.4.0; Experimental from v1.2 to v1.3 | `gateway.networking.k8s.io/v1/BackendTLSPolicy` (Standard, graduated in v1.4.0) **or** `gateway.networking.k8s.io/v1alpha2/TCPRoute` (Experimental) |
| `sessionPersistence.*` | v1.2.0 | **Experimental only** (still Experimental as of v1.5.1) | `gateway.networking.k8s.io/v1alpha2/TCPRoute` (Experimental) |

The chart fails fast at `helm template` time when `gateway.networking.k8s.io/v1` is present but the required channel marker is not. Detection is skipped offline (`helm template` without `--api-versions`).

### TLSRoute rule fields (`name`)

Every TLSRoute rule (in `tlsRoute.rules`, `tlsRoutes.<n>.rules`, and per-workload `deployments.<w>.tlsRoute.rules` / `statefulSets.<w>.tlsRoute.rules`) accepts one optional field beyond `backendRefs`:

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` (`SectionName`: lowercase RFC 1123 label, optionally dotted, max 253 chars) | Identifies the rule. MUST be unique within the route. |

**TLSRouteRule has no `matches`, `filters`, `timeouts`, `retry`, or `sessionPersistence`** — TLS is L4 passthrough; the spec defines only `name` and `backendRefs`.

> **Schema strictness.** Each rule entry is validated against a strict schema (`additionalProperties: false`) listing only `name`, `backendRefs`, `serviceName`, and `servicePort`. Unknown keys fail at `helm template` time.

TLSRoute itself is in the Gateway API Experimental channel (`gateway.networking.k8s.io/v1alpha2`), so any use of TLSRoute already presupposes Experimental CRDs — `name` adds no further channel requirement beyond TLSRoute itself.

### Autoscaler mutual exclusion

- `hpa.enabled: true` and `keda.enabled: true` on the same workload is fail-fast. Both manage `spec.replicas`; both running is undefined behaviour.
- `verticalPodAutoscaler` is orthogonal to both (touches `resources.requests`, not `replicas`).
- When any HPA-class scaler is on, `spec.replicas` is omitted from the rendered manifest so Helm doesn't bounce the count on every apply.

See [ADR 007](../05-adr/007-autoscaler-mutual-exclusion.md).

### Scheduling field inheritance

`tolerations`, `affinity`, `nodeSelector` and `topologySpreadConstraints` all follow the same rule: if the workload defines the field, it **replaces** the root value entirely. If the workload omits the field, the root value is inherited. To disable root inheritance without providing a replacement, set the field to an empty value (`tolerations: []`, `affinity: {}`, `topologySpreadConstraints: []`).

### Init containers and sidecars share one container shape

`deployments.<name>.initContainers` and `deployments.<name>.sidecars` (same under `statefulSets.<name>`) are maps keyed by container name. Both flow through the same renderer as the main container: `image`, `command`/`args`, `env`, `envSecrets`, `volumeMounts`, `resources`, `securityContext`, `lifecycle`. Both inherit the parent workload's `inherit.env` / `inherit.configMaps` / `inherit.configMapMount` flags. Neither inherits root-level `volumeMounts.<containerName>` — declare local mounts inline. Render order is `sortAlpha`; for `initContainers` Kubernetes runs them sequentially in declared order, so prefix names with `01-`, `02-`, … when run order matters (same convention as `jobGroups[*].tasks`). Reloader does not re-trigger init containers — they run only on Pod creation, so a config change rolls the workload and a fresh init pass runs. **Two exceptions for `initContainers`:** `probesEnabled` / probe blocks (`readinessProbe`, `livenessProbe`, `startupProbe`) and `lifecycle` are rejected — Kubernetes does not allow these on standard init containers, so `helm template` fail-fasts if either is set on an init entry.

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
