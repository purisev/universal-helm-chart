# 013 — Schema-driven validation, not template-side

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

The chart needs to reject invalid `values.yaml` early and clearly. There are two common ways to do that in Helm:

- **In templates** — sprinkle `{{- required "…" .Values.foo }}`, `{{- if not (regexMatch …) }}{{- fail "…" }}{{- end }}`, type checks via `kindIs`, and so on.
- **In a JSON Schema** at `values.schema.json`, which Helm validates automatically before any template renders.

Template-side validation reads naturally next to the rendering logic, but it has problems:

- It runs **per template**, so the same field gets validated multiple times — once per template that touches it. Drift between checks is easy.
- A single typo at install time triggers a wall of `fail` messages — one per template that hits the same root cause.
- Templates are evaluated lazily; some validation paths only fire when a feature is enabled. A user with `monitoring.enabled: false` could ship a misconfigured `monitoring.provider` for years and only learn about it the day they flip the switch.
- Templates have no concept of `additionalProperties: false` — a typoed key at the top level is silently ignored. Future-you wonders why a setting "doesn't work".

JSON Schema sidesteps every one of these.

## Decision

**All shape validation lives in `values.schema.json`. Templates render only.**

Specifically:

- Type checks (string vs number vs object) — schema.
- Enum constraints (`provider: prometheus | victoriametrics`) — schema.
- Required fields — schema.
- Regex / pattern checks (port name length, DNS-1123 label) — schema.
- `additionalProperties: false` on every closed object — schema.
- Conditional validation (`if/then/else`, `oneOf`, `anyOf`) — schema.

Templates may still **fail on invariant violations that depend on multiple value paths** — e.g. "HPA and KEDA both enabled" ([ADR 007](007-autoscaler-mutual-exclusion.md)) or "`hashSuffix: true` with `deletePolicy: HookSucceeded`" ([ADR 012](012-job-spec-hashing-for-idempotency.md)). These are cross-field invariants that JSON Schema can sometimes express but with poor error messages; a one-line `fail` in the template is clearer for the user.

Templates **must not** call `fail` for things the schema can express. If you find yourself reaching for a regex check in a template, write it in the schema instead.

## Consequences

**What this enables:**

- A single typo at the top level (`integrationss:` instead of `integrations:`) is caught at `helm template` / `helm install` time with a precise error from Helm's schema validator.
- Validation is consistent across `helm install`, `helm upgrade`, `helm template` and `helm lint`.
- IDEs and editors that understand JSON Schema (yaml-language-server / Red Hat YAML extension; JetBrains family) light up `values.yaml` with autocomplete and inline errors.
- Reading the schema is a quick way to see the chart's value shape — narrower than reading `values.yaml`'s 1200 lines.

**What it costs:**

- The schema is non-trivial (~700 lines for ~1200 lines of values). Maintaining it alongside `values.yaml` is a small ongoing tax.
- Cross-field invariants still need template-side `fail`s. The chart has a small number of these (HPA/KEDA mutual exclusion, jobGroups hash + delete policy guard) and each is documented in its own ADR.
- The schema uses JSON Schema draft `2020-12`. Older Helm versions may not support every keyword we use; tested with Helm 3.14+.

## Schema conventions

- **Closed objects use `additionalProperties: false`.** This catches typos at the leaf. Examples: `image`, `labels.standard`, `integrations.monitoring.defaults`.
- **Open maps use `additionalProperties: <object schema>` with patternProperties on keys.** Example: `deployments` (any DNS-1123 key, value must match the workload object schema).
- **Per-feature toggles use `if/then`** to make required fields conditional: e.g. when `integrations.eso.externalSecrets.<name>.dataFrom` is set, `secretStore` becomes required.
- **Keep regex sane.** Port names: `^[a-z]([-a-z0-9]*[a-z0-9])?$` and `length(name) <= 15`. Hostnames: standard DNS pattern. Anything more elaborate is suspect.

## Alternatives considered

- **Templates do everything.** Rejected: the failure mode is the one we want to leave behind.
- **No validation; trust the user.** Rejected: the chart's `values.yaml` is large and easy to typo.
- **A JSON Schema generated from `values.yaml` examples.** Rejected: round-tripping examples through a generator is brittle; we hand-write the schema and let humans review it.

## References

- `values.schema.json` — the schema itself
- Memory: "don't put regex/type validation in Helm templates; use schema" — informal team rule that this ADR formalises
- Helm schema documentation: https://helm.sh/docs/topics/charts/#schema-files
- Related: [ADR 004](004-maps-over-lists.md) (map keys are constrained by schema regex), [ADR 007](007-autoscaler-mutual-exclusion.md), [ADR 012](012-job-spec-hashing-for-idempotency.md)
