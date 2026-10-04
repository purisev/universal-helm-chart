# Changelog

What each release adds, changes and fixes. Values-file edits an upgrade may need are in the [migration guide](docs/03-reference/04-migration.md).

## 3.3.0 - unreleased

### Added

- `topologySpreadConstraints` renders `minDomains`, `nodeAffinityPolicy` and `nodeTaintsPolicy`, and the schema validates every field of an entry.
- `topologySpreadConstraints` on `jobGroups`, at group and job level.
- A GitHub Release for every tag, carrying the packaged chart, its Sigstore signature and build provenance.

### Fixed

- A root `podDisruptionBudget.maxUnavailable` renders without clearing `minAvailable` first.

## 3.2.0 - 2026-09-19

### Added

- `naming.omitWorkloadSuffix` for single-workload releases: resource names and labels drop the workload name.
- Per-workload Service name override through `service.nameOverride`.
- `keda.advanced` is passed through to the ScaledObject.
- A StatefulSet gets its own metrics Service when `exposeService` is enabled.

### Changed

- The `metrics` container port is declared on the main container of a Deployment or StatefulSet only. Finished Jobs from 3.1.0 have to be deleted before the upgrade; see the migration guide.
- `containerPort` is derived from `service.port` when `targetPort` is absent.
- Two ConfigMaps that claim one name fail at render time.
- Service port entries, named `targetPort` values and disabled headless Service names are validated at render time.

### Fixed

- jobGroup and External Secrets labels stay off the workload selector.
- Examples that could not be installed.
- `LICENSE` carries the verbatim Apache-2.0 text.

### Security

- Workflow actions are pinned by commit SHA and workflow tokens are restricted to the permissions each job needs.

## 3.1.0 - 2026-08-19

### Added

- `hostnames` and `parentRefs` are evaluated with `tpl`.

### Fixed

- StatefulSet rendering with more than one entry.

## 3.0.1 - 2026-08-19

### Fixed

- Argo CD no longer reports StatefulSet `volumeClaimTemplates` and HTTPRoute, GRPCRoute and TLSRoute `parentRefs` and `backendRefs` as permanently OutOfSync under `ServerSideApply=true`.

## 3.0.0 - 2026-08-16

### Changed

- **Breaking:** `statefulSets.<name>.service` always renders its own independent Service. Headless-specific fields (`ports`, `annotations`, `publishNotReadyAddresses`, `ipFamilies`, `ipFamilyPolicy`) moved from `service.*` to `headlessService.*`.
- Service `port` and `targetPort` default to each other.

### Added

- Deployment `spec.paused`, ServiceAccount `automountServiceAccountToken`, ClusterRole `aggregationRule`, container `resizePolicy`, pod-level `resourceClaims`.
- StatefulSet `ordinals.start` and `persistentVolumeClaimRetentionPolicy`, PodDisruptionBudget `unhealthyPodEvictionPolicy`, Service `internalTrafficPolicy`.
- jobGroups `completions`, `parallelism`, `suspend`, `podFailurePolicy`, `podReplacementPolicy` and Indexed Jobs.
- An end-to-end suite that installs the chart on kind clusters.
- Documentation site at <https://uhc.purisev.com>.

### Security

- `SECURITY.md`, a Trivy misconfiguration scan in CI, keyless signing of the published chart with cosign, OpenSSF Scorecard analysis.
- A pull request branch name is no longer interpolated into a shell command in CI.

## 2.1.0 - 2026-05-08

### Added

- HTTPRoute rule-level `name`, `timeouts`, `retry` and `sessionPersistence`.
- GRPCRoute rule-level `name` and `sessionPersistence`, TLSRoute rule-level `name`.

### Fixed

- TLSRoute renders as `gateway.networking.k8s.io/v1alpha2`.

## 2.0.0 - 2026-05-03

### Changed

- **Breaking:** `dbJob`, `initJob`, `postSync` and `cronJobs` are replaced by `jobGroups`.
- **Breaking:** `envDev` and `envProd` are collapsed into a single root `env`.
- **Breaking:** ecosystem settings moved under `integrations.*`, and the remaining list-shaped values became maps or lists of strings.
- **Breaking:** scheduling fields on a workload replace the root value; `inheritRootSchedParams` is removed.
- Constructed resource names longer than 63 characters fail at render time.

### Added

- Monitoring through ServiceMonitor, PodMonitor or annotations, for Prometheus and VictoriaMetrics.
- `initContainers` on Deployments and StatefulSets.
- HPA for StatefulSets.
- Documentation tree, Architecture Decision Records and examples.

## 1.1.0 - 2026-04-05

### Added

- Gateway API routes.
- Argo CD Image Updater resource.

### Changed

- `ingressClassName` is optional and accepts any ingress class.

## 1.0.0 - 2026-01-02

First public release.
