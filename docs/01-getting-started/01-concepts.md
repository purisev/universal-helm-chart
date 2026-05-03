# Concepts

This page is the "why" of the chart — what it actually does for you that a hand-rolled `helm create` chart doesn't, and the small set of ideas you need in your head to read any `values.yaml`.

For the full design rationale of any item below, follow the linked ADR.

## What this chart is

**One Helm chart that covers every common Kubernetes workload shape — and the supporting cast every release ends up needing.** Deployment, StatefulSet, Job and CronJob, plus their Services, Ingresses, Gateway API routes, autoscalers, monitors, ExternalSecrets, NetworkPolicies, PodDisruptionBudgets, RBAC, sync-wave annotations and Image Updater configs.

It replaces the typical pattern of "one chart per service, all subtly different" with **one well-tested template** consumed by N services. Bug fixes and security defaults land once and propagate to every consumer on next upgrade. ([ADR 001](../05-adr/001-universal-chart-scope.md))

## The four primitives

These four ideas explain almost every line of `values.yaml`. The rest is detail.

### 1. Workloads as keyed maps

`deployments`, `statefulSets` and `jobGroups` are **maps**, not lists. The map key is the workload's logical name and becomes part of the rendered resource name (`<release-fullname>-<key>`). One release can ship many workloads of the same kind without template duplication, and overlay values can target a single entry without rewriting the rest.

```yaml
deployments:
  api:
    image:
      repository: my/api
      tag: v1
    service:
      ports:
        http:
          port: 80
          targetPort: 8080
  worker:
    image:
      repository: my/worker
      tag: v1
    service:
      enabled: false
```

→ two Deployments, one Service for the API, one shared release. ([ADR 002](../05-adr/002-multi-workload-keyed-maps.md))

### 2. `jobGroups` for both Job and CronJob

A `jobGroup` has a `kind` (`Job` | `CronJob`) and a `jobs:` map. Per-job fields override group-level fields with shape-specific rules — scalars take the job's value or fall back to the group's; lists concat group-then-job; nested maps (`env`, `image`, `resources`, `securityContext`, `inherit`, `hooks.*`, etc.) deep-merge with the job winning on key collision; name-keyed maps (`volumes`, `volumeMounts`) replace whole entries by name. The same shape covers schema migrations, nightly cleanups, smoke checks. ([ADR 005](../05-adr/005-jobgroups-unification.md))

Crucially: every Job's name carries an **8-char hash of its rendered spec**. Same spec → same name → Argo CD/Flux see "no change" and skip. Spec changes → new name → new Job runs once. Old Jobs are GC'd by `ttlSecondsAfterFinished`. **Migrations never re-run on every sync.** ([ADR 012](../05-adr/012-job-spec-hashing-for-idempotency.md))

### 3. `integrations`

Every external system — Argo CD, Stakater Reloader, External Secrets Operator, Prometheus / VictoriaMetrics Operators, KEDA — lives under `integrations.*` with an `enabled` toggle and a config block. One block to skim, one place to add the next integration. ([ADR 006](../05-adr/006-integrations-namespace.md))

### 4. Layered inheritance with explicit override

Environment variables, ConfigMap mounts, Secret mounts, labels, annotations, scheduling parameters — all cascade through four layers:

```
global  →  root  →  workload  →  container
```

Maps replace per key, lists concat, `inherit.*` flags opt out per-workload. A platform team can ship `OTEL_EXPORTER_OTLP_ENDPOINT` in `global.env` once and have every workload pick it up; a single noisy worker can opt out without touching ancestor configuration. ([ADR 003](../05-adr/003-layered-inheritance-and-override.md))

## Killer features

Things this chart gives you that you'd otherwise build yourself.

### One chart, every common workload

Deployment, StatefulSet, Job, CronJob — all in one chart, all sharing labels / inheritance / monitoring / secrets / sync-waves. No subcharts. No "but this is the API chart, the migrations chart is over there." ([ADR 001](../05-adr/001-universal-chart-scope.md))

### Multiple workloads per release

A real microservice often ships as `api + worker + cron + migrate` — four resources that share an image, env, secrets and labels. Declare them once, in one values file, and the chart renders four resources with the right cross-references. ([ADR 002](../05-adr/002-multi-workload-keyed-maps.md))

### Job idempotency under GitOps

Argo CD on a 1-minute sync interval doesn't re-run your migrations. Hash-suffixed Job names make the Job's identity a function of its spec. Image bump → new Job. Spec unchanged → no Job runs. With Argo CD Image Updater + `update-strategy: digest`, even mutable tags (`dev`, `main`) get re-runs on actual image change, not on tag-name unchanged. ([ADR 012](../05-adr/012-job-spec-hashing-for-idempotency.md))

### Multi-provider monitoring

A three-axis matrix: **provider** (Prometheus | VictoriaMetrics) × **discovery** (CRD | annotations) × **target** (service | pod). Eight combinations behind one mental model. Chart works in clusters running Prometheus Operator, VictoriaMetrics Operator, both, or neither. Switching providers is one values key. ([ADR 008](../05-adr/008-multi-provider-monitoring.md))

### Auto-exposed metrics port

`integrations.monitoring.defaults.exposeService.enabled: true` — the chart appends a `metrics` port to every Service and pod template, fixed name, last position. Workloads with no main Service get a dedicated metrics-only Service. No more boilerplate port pairs across N workloads. ([ADR 016](../05-adr/016-metrics-port-auto-exposure.md))

### Dual networking stack

Ingress and Gateway API co-exist. Pick whichever fits the controller you have. Each has both a singleton shape (one routing object per release, the common case) and a multi-resource map (one per controller / parent / hostname). Per-workload route shorthand merges into the singleton with explicit `priority` for ordering. Cross-namespace `ReferenceGrant` is a one-block declaration. ([ADR 009](../05-adr/009-dual-networking-stack.md))

### Argo CD sync-waves out of the box

Clean first-time syncs in Argo CD: ServiceAccount → SecretStore → ExternalSecret/ConfigMap → Service → workloads → derived (HPA/VPA/monitors) → routes. No flickering "Degraded" on a fresh install. Override per kind, opt-out per kind, disable wholesale — your call. ([ADR 010](../05-adr/010-argocd-sync-waves.md))

### External Secrets Operator with smart disambiguation

`SecretStore` and `ExternalSecret` resources, both `data` (map keyed by `secretKey`) and `dataFrom` (list, bulk extraction). Chart-owned ConfigMaps and Secrets win over external references on name collisions — no silent shadowing surprises. ESO target template annotations propagate to the generated Secret so Reloader picks up rotations. ([ADR 015](../05-adr/015-eso-data-vs-datafrom.md))

### Reloader integration

One toggle injects `reloader.stakater.com/auto: "true"` onto Deployments, StatefulSets, ConfigMaps and ExternalSecret target templates. Secret rotation in your Vault store → ESO updates the K8s Secret → Reloader bounces the workload. End to end. ([ADR 017](../05-adr/017-reloader-annotation-injection.md))

### Argo CD Image Updater

Shorthand mode tracks an image with `update-strategy: digest`, writing the new tag back via Argo CD parameter overrides. Mutable tags become safe — the digest is what changes, not the tag name. Combined with hash-suffixed Jobs, migrations re-run on actual image change. (See `integrations.argocd.imageUpdater` in `values.yaml`.)

### HPA / KEDA / VPA with mutual-exclusion guards

HPA on metrics, KEDA on events, VPA on resource requests. The chart fail-fasts on HPA + KEDA on the same workload (they'd both fight for `replicas`). VPA is orthogonal. `spec.replicas` is omitted from the rendered manifest when an HPA-class scaler is on, so Helm doesn't bounce the count on every apply. ([ADR 007](../05-adr/007-autoscaler-mutual-exclusion.md))

### Standard-wins labels with invariant selectors

Set `commonLabels` for fleet-wide labels (cost-center, team, environment) without ever risking a selector break. The chart-managed `app.kubernetes.io/{name,instance}` are emitted on workload selectors **regardless of any toggle** — the API server forbids selector mutation, and we make sure you can't accidentally mutate them. The other `app.kubernetes.io/*` labels follow your toggles, on singletons. ([ADR 011](../05-adr/011-standard-wins-labels-and-invariant-selectors.md))

### Schema-driven validation

`values.schema.json` catches typos at install time, not at runtime. `additionalProperties: false` on closed objects, conditional validation via `if/then`, regex on map keys. IDEs with yaml-language-server light up `values.yaml` with autocomplete and inline errors. Templates render only — no `regexMatch` / `kindIs` / `required` sprinkled across helpers. ([ADR 013](../05-adr/013-schema-driven-validation.md))

### Maps over lists, deterministic ordering

The whole values API leans on maps with a natural key. Overlay merging targets one entry; duplicates are caught by the YAML parser; per-entry disabling is `enabled: false`. Iteration is alphabetical except where convention says otherwise (`http` first, `metrics` last for ports; explicit `priority` for Gateway API rules). `helm template` on identical inputs produces byte-identical output. ([ADR 004](../05-adr/004-maps-over-lists.md), [ADR 014](../05-adr/014-deterministic-ordering.md))

### Sane secure defaults

Out of the box: `runAsNonRoot: true`, `runAsUser: 1000`, `seccompProfile: RuntimeDefault`, `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`, `automountServiceAccountToken: false`, `terminationGracePeriodSeconds: 30`. Override per workload. Pod Security Standards "Restricted" level without thinking about it.

### Tested

The chart ships with a comprehensive `helm-unittest` suite that runs on every PR. Templates are dense; the test suite catches drift before it lands on consumers. Fixtures double as executable documentation for non-trivial scenarios. ([ADR 018](../05-adr/018-testing-with-helm-unittest.md))

## What this chart is **not**

- **A platform.** It renders Kubernetes resources from values. It does not deploy itself, manage namespaces, or own cluster-wide policy.
- **A subchart factory.** No nested subcharts of its own — composition is by `values.yaml`, not by chart hierarchy. *That said, this chart works **excellently as a subchart itself**:* drop it under `dependencies:` in your umbrella chart and the parent's `global.env`, `global.image`, etc. propagate into every workload via the four-layer cascade. One umbrella chart consuming N instances of this chart is a first-class use case.
- **A DaemonSet / ReplicaSet shop — for now.** Out of scope in the current release ([ADR 001](../05-adr/001-universal-chart-scope.md)). DaemonSet support may land later if there is demand; ReplicaSet is unlikely (Deployment is the right abstraction in almost every case).
- **Opinionated about your CI/CD tool.** Examples cover Argo CD (single + multi-source), Flux (`OCIRepository` + `HelmRelease`) and the plain `helm` CLI. Pick whichever; the chart doesn't care.

## Where to go next

- Need to install the chart → [`02-installation.md`](02-installation.md).
- Just want to deploy something quickly → [`03-quickstart.md`](03-quickstart.md).
- Want to copy a working scenario → [`../02-examples/`](../02-examples/).
- Want the long-form rationale for any feature above → [`../05-adr/`](../05-adr/).
- Want to look up a specific values key → [`../03-reference/`](../03-reference/).
