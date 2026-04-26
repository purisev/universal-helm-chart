# 015 — ESO `data` vs `dataFrom` and chart-vs-external disambiguation

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

External Secrets Operator (ESO) gives two ways to extract values from a backend (Vault, AWS, GCP, etc.) into a Kubernetes Secret:

- **`data[]`** — explicit per-field mapping. Each entry says: "fetch this `remoteKey`+`property` and put it in the resulting Secret under this `secretKey`." Granular, predictable, type-checked.
- **`dataFrom[]`** — bulk extraction. "Fetch the whole `remoteKey` and merge all its fields into the resulting Secret." Saves typing when the remote secret is already shaped right; obscures which fields end up in K8s.

Both have legitimate uses. The chart needs to support both without making the values shape ambiguous.

A second disambiguation problem: the chart manages its own `configMaps` (under `.Values.configMaps`) and reads external `envConfigMaps` (a list of names). When a user lists `app-config` under `envConfigMaps` and also defines a `configMaps.app-config` block with its own `data`, which `app-config` is mounted? The chart-managed one (named `<release-fullname>-app-config`) or some external one called literally `app-config`?

The same problem exists for ExternalSecret targets: a `targetName` collision with a chart-owned ConfigMap or a user-supplied Secret name.

## Decision

### `data` vs `dataFrom`

In `values.yaml`:

- **`data` is a map** keyed by the resulting Secret's field name (`secretKey`). Map key → `spec.data[].secretKey` in the rendered ExternalSecret. This makes `data` deterministic and overlay-mergeable per [ADR 004](004-maps-over-lists.md):
  ```yaml
  externalSecrets:
    db-creds:
      data:
        DB_PASSWORD:                    # ← becomes data[].secretKey
          remoteKey: my-app/db
          property: password
  ```
- **`dataFrom` is a list.** A natural unique key doesn't exist (the same `remoteKey` can appear twice with different `conversionStrategy` / `decodingStrategy` overrides), and order can matter for merge semantics in some backends.
- **Both can coexist** in one ExternalSecret. ESO merges them; explicit `data` entries win on conflicting keys.

### Chart-owned vs external naming collisions

The chart computes the rendered name in this order:

1. **Chart-owned name first.** If the values reference a name that *also* appears as a key in `.Values.configMaps` (or `.Values.integrations.eso.externalSecrets`), the rendered reference points at the chart-managed resource (`<release-fullname>-<name>`).
2. **External otherwise.** The reference is rendered as the literal name.

Implementation lives in `templates/_helpers.tpl:uhc.containerSpecWithOptions` (the envFrom resolution) and in the schema's `additionalProperties` rules.

The chart documents this explicitly in the `envConfigMaps` block of `values.yaml`:
> On collision (an external CM and a chart-owned `configMaps.<name>` with the same name) the chart-owned one wins and the external CM is shadowed.

## Consequences

**What this enables:**

- Granular `data` declarations get all the benefits of map shape: overlay merging, duplicate prevention, per-key disabling.
- Bulk `dataFrom` stays expressible without forcing artificial keys.
- The "two ConfigMaps with the same name" failure mode becomes impossible: the chart picks one and silently shadows the other. Users see exactly one `app-config` in the rendered Pod.

**What it costs:**

- "Chart-owned wins" is silent. A user who *intended* to reference an external `app-config` and happens to have a `configMaps.app-config` block in their values will get the chart-owned one. The chart's defence is that having both is itself a code smell — pick distinct names if you need both. Documented in the `envConfigMaps` block of `values.yaml`.
- `dataFrom` doesn't dedupe on collision with explicit `data` in the chart layer; ESO does the dedupe on the backend at apply time. We accept this inconsistency because dedupe in the chart would require knowing each backend's per-field mapping, which we don't.

## Worked example

```yaml
configMaps:
  app-config:
    enabled: true
    data:
      LOG_LEVEL: info

envConfigMaps:
  - app-config       # → resolves to <release>-app-config (chart-owned wins)
  - other-team-cm    # → resolves to other-team-cm (external)

integrations:
  eso:
    externalSecrets:
      db-creds:
        secretStore: vault-store
        targetName: db-creds            # → K8s Secret named db-creds
        data:
          DB_PASSWORD:
            remoteKey: my-app/db
            property: password
        dataFrom:
          - remoteKey: my-app/redis
            conversionStrategy: Default
```

Result: one ConfigMap (`<release>-app-config`) shadowing nothing because no collision exists; `envConfigMaps` references the chart-owned one. One ExternalSecret with two extraction methods feeding one K8s Secret.

## Alternatives considered

- **`data` as a list.** Rejected: loses overlay-merge wins, loses duplicate prevention.
- **`dataFrom` as a map.** Rejected: requires inventing synthetic keys (`bulk_1`, `bulk_2`); duplicates are legitimate.
- **External-wins on name collisions.** Rejected: the chart-owned ConfigMap presumably has the right value (it's in the chart's values); the external reference is presumed to be the older, possibly stale source.
- **Fail loudly on collision.** Rejected: the warning belongs in the schema; a render-time fail is too noisy for a configuration smell.

## References

- `values.yaml` — the `integrations.eso.externalSecrets` block (narrative on `data` vs `dataFrom`) and the `envConfigMaps` block (chart-owned vs external resolution).
- `templates/externalsecret.yaml` — renders both `data` and `dataFrom`.
- `templates/_helpers.tpl` — `uhc.containerSpecWithOptions` (envFrom resolution).
- Tests: `tests/externalsecret_test.yaml`; fixtures `es-data.yaml`, `es-mixed.yaml`, `es-datafrom-auto.yaml`, `es-datafrom-overrides.yaml`.
- Related: [ADR 004](004-maps-over-lists.md), [ADR 006](006-integrations-namespace.md).
