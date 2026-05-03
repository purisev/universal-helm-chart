# 003 — Layered inheritance and explicit override

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

A real release fans out across several scopes that all want to inject the same kinds of configuration:

- the **fleet** scope — env vars common to every chart instance in a cluster (`OTEL_EXPORTER_OTLP_ENDPOINT`, region, environment name);
- the **release** scope — env vars and labels common to every workload in this app (`SERVICE_NAME`, app version);
- the **workload** scope — env vars specific to one Deployment ("the worker uses a different log level");
- the **container** scope — env vars specific to a sidecar.

If each layer carries its own merge rules implemented inline in templates, the result is fragile: it's easy to forget to inherit one piece (and pods miss a critical env var) or to double-inject another (and `envFrom` lists grow). We need one consistent answer that covers env vars, ConfigMap mounts, Secret mounts, volumes, scheduling parameters and labels.

We also need a way to **opt out**. Most workloads should inherit everything; a small number need to escape — for example, a sidecar that talks to a different secret store than the main container, or a CronJob that should not pick up the global Datadog agent annotation.

## Decision

A **four-layer cascade** with **explicit opt-out** at the inheriting layer:

```
global  →  root  →  workload  →  container
```

At each layer the chart applies these merge rules:

| Kind                     | How layers combine        |
|--------------------------|---------------------------|
| Maps (env vars, labels, annotations) | **Replace per key** — later layer's value wins on collision; non-colliding keys union. |
| Lists (`envSecrets`, `envConfigMaps`, `hostAliases`) | **Concat** — earlier-layer entries appear first, later-layer entries appended. Duplicates are not deduplicated; map-keyed inheritance (`inherit.configMapMount.<name>: false`) is the way to suppress one. |
| Scheduling fields (`tolerations`, `affinity`, `nodeSelector`, `topologySpreadConstraints`) | **Workload replaces root** — if the workload defines the field, it takes full ownership and the root value is ignored. If the workload omits the field entirely, the root value is inherited. To explicitly disable root inheritance without providing a replacement, set the field to an empty value (`tolerations: []`, `affinity: {}`, `topologySpreadConstraints: []`). |
| Volumes (map keyed by volume name) | **Replace by key** — same rule as maps. Cannot deep-merge: a volume `data` cannot be partially `emptyDir` and partially `configMap`. See [ADR 004](004-maps-over-lists.md). |

The opt-out for env and configMap inheritance is expressed via `inherit.*` flags:

```yaml
deployments:
  worker:
    inherit:
      env:
        global: true            # opt out of global.env  → false
        root: true              # opt out of root env    → false
      envSecrets: true          # opt out of root envSecrets in envFrom → false
      configMaps: true          # opt out of root envConfigMaps
      configMapMount: true      # or fine-grained: configMapMount.<name>: false
```

Default values are all `true` — i.e. inherit everything. Opt-out is a deliberate, visible setting in the workload that needs it.

For `jobGroups`, an additional override level applies between a group and one of its jobs — distinct from the layer cascade above and with its own merge rules. Job-level fields override group-level fields as follows: scalars take the job value when set, otherwise the group's; lists (`envSecrets`, `envConfigMaps`, `tolerations`) are concatenated group-then-job; nested maps (`env`, `image`, `securityContext`, `podSecurityContext`, `resources`, `nodeSelector`, `affinity`, `inherit`, `hooks.argocd`, `hooks.helm`, `metadataAnnotations`) **deep-merge** with the job winning on key collision; `volumes` and `volumeMounts` (maps keyed by name) replace **whole entries** by name — the chart does not recurse into a single volume/mount, because k8s volume kinds are mutually exclusive (a name is either an `emptyDir` or a `configMap`, never both). See [ADR 005](005-jobgroups-unification.md).

## Consequences

**What this enables:**

- **Cluster-wide defaults** in `global.env` propagate everywhere automatically (Helm's subchart `global:` mechanism). A platform team can ship an OTel endpoint in one place.
- **Predictable overrides.** "Workload value wins for maps; lists concat" is a single sentence to remember.
- **Local escape hatches** without touching ancestor configuration. A bursty worker that should not inherit a Datadog agent annotation simply sets `inherit.configMapMount.datadog: false`.

**What it costs:**

- The merge rules differ between maps, lists, and scheduling fields; contributors must remember which is which. We mitigate this with [ADR 004](004-maps-over-lists.md) — collections become maps unless they truly cannot — and with the cross-cutting rules section in [`docs/03-reference/01-values.md`](../03-reference/01-values.md).
- "Inheritance" is *not* deep merge of arbitrary structures. Volumes, env vars and configMap entries inherit by *whole entity* keyed by name. This is a feature: deep-merging a volume that's `emptyDir` at one layer and `configMap` at another would produce nonsense.
- Helpers carrying inheritance logic (`uhc.envVars`, `uhc.envFrom`, `uhc.containerSpecWithOptions`, `uhc.sidecarsSpec` in `templates/_env.tpl` and `templates/_workload.tpl`; `uhc.jobGroupSpec` in `templates/_jobs.tpl`) are non-trivial. They are tested aggressively via helm-unittest.

## Examples

```yaml
# global.env propagates to every container in every workload
global:
  env:
    OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4318

# Release-level env applies to every workload in this release
env:
  SERVICE_NAME: orders

deployments:
  api:
    # No 'inherit' block — inherits both global and release env
    env:
      LOG_LEVEL: info        # adds to the merged set; wins on collision
  reaper:
    inherit:
      env:
        global: false        # this workload skips global.env
    env:
      LOG_LEVEL: warn
```

The resulting effective env in `deployments.api`'s container:
`OTEL_EXPORTER_OTLP_ENDPOINT, SERVICE_NAME, LOG_LEVEL` (plus the chart-injected `NAMESPACE` from `fieldRef`).

In `deployments.reaper`'s container:
`SERVICE_NAME, LOG_LEVEL` only — `OTEL_EXPORTER_OTLP_ENDPOINT` is suppressed by the opt-out.

## Alternatives considered

- **No inheritance — each workload restates everything.** Rejected: defeats the universal chart goal and re-creates copy-paste drift inside one chart.
- **Deep merge with strategic-merge-patch semantics.** Rejected: surprising behaviour around list merging (replace vs append vs merge-by-key); would require us to re-implement a substantial subset of `kubectl apply` semantics in templates.
- **Producer-side opt-out** — env vars at `global.env` carrying their own per-workload exclusion list. Rejected: scatters per-workload knowledge into ancestor configuration; harder to read.

## References

- `templates/_env.tpl` — `uhc.envVars`, `uhc.envFrom`. `templates/_workload.tpl` — `uhc.containerSpecWithOptions`, `uhc.sidecarsSpec`, `uhc.scheduling`. `templates/_jobs.tpl` — `uhc.jobGroupSpec`.
- [`docs/03-reference/01-values.md`](../03-reference/01-values.md) — Cross-cutting rules: env merge order, scheduling field inheritance, jobGroups merge.
- Related: [ADR 002](002-multi-workload-keyed-maps.md), [ADR 004](004-maps-over-lists.md), [ADR 005](005-jobgroups-unification.md).
