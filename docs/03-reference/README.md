# Reference

The authoritative per-field source is [`values.yaml`](../../values.yaml) (heavily annotated) and [`values.schema.json`](../../values.schema.json) (machine-checkable shape). The pages here add cross-cutting context that those files don't aggregate.

- [`01-values.md`](01-values.md) — topical index of every top-level key plus the cross-cutting rules (env merge, label precedence, port ordering, jobGroups merge, autoscaler exclusion, chart-owned vs external resolution).
- [`02-schema.md`](02-schema.md) — what the schema does and doesn't catch, schema layout, and IDE setup for autocomplete and inline validation (yaml-language-server / Red Hat YAML, JetBrains, `helm lint`, `ajv-cli`).
- [`03-compatibility.md`](03-compatibility.md) — Helm version, Kubernetes APIs the chart renders, and the CRD groups/versions for each optional integration.
- [`04-migration.md`](04-migration.md) — values-file edits required when upgrading along the `release-2.0.0` line.
