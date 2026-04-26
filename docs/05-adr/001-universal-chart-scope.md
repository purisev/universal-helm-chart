# 001 — Universal chart: one chart for all common workloads

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

Most teams running Kubernetes accumulate a stack of "almost the same" Helm charts: one for the API service, one for the worker, one for the cron jobs, one for the migration job, one for the gRPC backend. Each chart copies and slowly diverges in how it computes labels, how it wires in monitoring, how it reads secrets, how it writes pod security context. Bug fixes in one chart don't propagate. The blast radius of any change is small per chart but the aggregate cost — review burden, audit gaps, drift — is large.

The constraints we live with:

- Workloads we ship are conventional: Deployment, StatefulSet, Job, CronJob.
- Most workloads need the same supporting cast: Service, Ingress / Gateway API, ServiceMonitor, ExternalSecret, RBAC, NetworkPolicy, PDB.
- We deploy through Argo CD and Flux — both expect a single chart reference per Application / HelmRelease.
- We want a single place to roll out a security tightening (e.g. a `seccompProfile` default) and have every service pick it up on next deploy.

## Decision

Ship **one** Helm chart that covers all the common workload kinds and their typical neighbours. A release using this chart can declare any combination of:

- multiple Deployments (via the `deployments` map);
- multiple StatefulSets (`statefulSets`);
- multiple Job and CronJob bundles (`jobGroups`);
- their Services, Ingresses and Gateway API routes;
- HPA / KEDA / VPA;
- ServiceMonitor / PodMonitor (Prometheus or VictoriaMetrics flavours);
- ESO `ExternalSecret` and `SecretStore` resources;
- ConfigMaps owned by the chart;
- ServiceAccount, RBAC, NetworkPolicy, PDB, Argo CD `ImageUpdater`, ReferenceGrant.

Everything is opt-in via `values.yaml`. A release that only fills in `deployments.web` produces only a Deployment and (if `service.enabled`) a Service.

## Consequences

**What this enables:**

- One place to centralise security defaults (`podSecurityContext`, `securityContext`, `automountServiceAccountToken: false`) — see lines 485–504 in `values.yaml`.
- Multiple workloads in a single release co-exist and share `global.env`, common labels, common annotations, and inherited config — see [ADR 003](003-layered-inheritance-and-override.md).
- Bug fixes and feature additions land once and cover every consumer on next chart upgrade.
- A consistent label / selector contract across all services in a fleet — see [ADR 011](011-standard-wins-labels-and-invariant-selectors.md).

**What it costs:**

- `values.yaml` is large (~1200 lines) — readers face a learning cliff. Mitigations: a JSON schema with strict shape validation ([ADR 013](013-schema-driven-validation.md)), the [`docs/02-examples/`](../02-examples/) catalogue, and the section index in `values.yaml` itself.
- Some niche workload types are deliberately out of scope.
- The chart's blast radius on a change is large — every consumer is a downstream. Mitigations: helm-unittest snapshots ([ADR 018](018-testing-with-helm-unittest.md)) and conservative versioning.

## Out of scope (deliberately not shipped)

- DaemonSet — uncommon in our deployments and has different scaling / scheduling semantics.
- ReplicaSet, ReplicationController — superseded by Deployment.
- Pod (bare) — almost always wrong outside of debugging.
- Plain `Endpoints` / `EndpointSlice` — the chart owns Services, not their endpoints.
- Custom resources outside the integrations we've explicitly modelled (Argo CD `Application`, Flux `HelmRelease`, etc.) — those *consume* this chart, they don't belong inside it.

This list is the contract. Adding a new workload kind is an ADR-worthy decision, not a routine PR.

## Alternatives considered

- **One chart per workload kind.** Rejected: drift, copy-paste defaults, no DRY for shared neighbours (Service, monitoring, secrets).
- **A library chart consumed by per-service application charts.** Rejected: would still leave each service team with a chart to maintain; the universal chart already targets the same DRY goal with a flatter operational model.
- **A code generator (Cookiecutter / Yeoman) producing a chart per service.** Rejected: snapshots configuration at generation time; fixes don't propagate without re-running the generator and resolving merge conflicts.

## References

- `Chart.yaml` (chart name, version)
- `values.yaml` lines 1–50, 485–504 (chart-wide defaults)
- Related: [ADR 002](002-multi-workload-keyed-maps.md), [ADR 003](003-layered-inheritance-and-override.md), [ADR 006](006-integrations-namespace.md)
