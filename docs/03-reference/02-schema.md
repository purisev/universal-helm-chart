# Schema and IDE setup

`values.schema.json` is a JSON Schema (draft 2020-12) that Helm runs against your `values.yaml` on every render. It catches typos, wrong types and out-of-enum values **before** templates execute, so the failure mode is a clear "this field has the wrong shape" rather than a confusing rendered manifest.

## What the schema catches

- field types (string, integer, boolean, object, array);
- enum constraints (`pullPolicy: Always | IfNotPresent | Never`, `provider: prometheus | victoriametrics`, …);
- closed objects (`additionalProperties: false`) — typoed keys at the leaf are rejected;
- minimum / maximum on integers;
- regex on map keys (port names ≤15 chars, DNS-1123 labels, …).

## What the schema doesn't catch

Cross-field invariants that depend on values in different sections — for example "HPA and KEDA on the same workload is invalid" or "`hashSuffix: true` together with a delete-policy that removes the Job after success". These live as `fail` calls in the templates. Rationale: [ADR 013 — Schema-driven validation](../05-adr/013-schema-driven-validation.md).

## Schema layout

Two recurring shapes:

**Closed object** — every field is enumerated; typos fail.

```json
"image": {
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "repository": { "type": "string" },
    "tag":        { "type": "string" },
    "pullPolicy": { "type": "string", "enum": ["Always", "IfNotPresent", "Never"] }
  }
}
```

**Open map** — keys are user-provided names (workloads, ports, hosts), values must match a schema.

```json
"deployments": {
  "type": "object",
  "additionalProperties": { "$ref": "#/$defs/workload" }
}
```

For the full schema source, see [`values.schema.json`](https://github.com/purisev/universal-helm-chart/blob/main/values.schema.json).

## IDE setup

### `yaml-language-server` / Red Hat YAML extension (VS Code, Neovim, others)

Add a directive at the top of any values file you author:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/purisev/universal-helm-chart/v3.1.0/values.schema.json
deployments:
  api:
    image:
      repository: nginx
      tag: "1.27"
```

Autocompletion, hover docs and inline error squiggles work from this point on.

### JetBrains IDEs (IntelliJ, GoLand, PyCharm, …)

`Settings` → `Languages & Frameworks` → `Schemas and DTDs` → `JSON Schema Mappings`:

- **Schema file or URL:** `https://raw.githubusercontent.com/purisev/universal-helm-chart/v3.1.0/values.schema.json`
- **Schema version:** JSON Schema 2020-12 (the latest)
- **File path pattern:** `*values*.yaml` (or per-project glob).

### `helm lint`

Schema validation runs as part of every `helm lint` and `helm install`/`upgrade`. No setup required. CI calls it on every PR.

## Manual validation outside Helm

For a fast editor pre-check loop without Helm in the path:

```bash
ajv validate \
  --spec=draft2020 \
  -s values.schema.json \
  -d values.yaml
```

Use this when iterating on overlay values in a config repo where Helm isn't installed.

## Pinning the schema URL

The `v3.1.0` segment in the schema URL above is a git tag. Replace it with the chart version you're targeting (or a branch name if you're tracking a development line). For an OCI artifact, the schema is bundled inside the chart and pulled on `helm template`/`helm install` automatically — IDE setup is only needed when authoring values outside an active `helm` invocation.
