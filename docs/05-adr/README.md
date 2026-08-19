# Architecture Decision Records

ADRs capture the reasoning behind the chart's load-bearing design choices — the things that would be hard to reverse and the things a new contributor would otherwise have to reverse-engineer from `values.yaml`. For working configurations rather than rationale, see [`../02-examples/`](../02-examples/).

## Numbering convention

Numbers encode **importance**, not chronology:

- `001` is the most foundational decision — everything else assumes it.
- The tail (`015`–`018`) covers narrower refinements.
- New ADRs append at the next free number; if a new decision belongs higher in the stack, **don't renumber existing ADRs** — link to it from the relevant ADR(s) and update this index.

Three-digit prefix; one decision per file.

## Index

| #   | File | Status |
|-----|------|--------|
| 001 | [Universal chart: one chart for all common workloads](001-universal-chart-scope.md) | Accepted |
| 002 | [Multi-workload via keyed maps in a single release](002-multi-workload-keyed-maps.md) | Accepted |
| 003 | [Layered inheritance and explicit override](003-layered-inheritance-and-override.md) | Accepted |
| 004 | [Maps over lists as the default collection shape](004-maps-over-lists.md) | Accepted |
| 005 | [`jobGroups` unifying Job and CronJob](005-jobgroups-unification.md) | Accepted |
| 006 | [`integrations` namespace for ecosystem knobs](006-integrations-namespace.md) | Accepted |
| 007 | [Autoscaler mutual exclusion (HPA / KEDA / VPA)](007-autoscaler-mutual-exclusion.md) | Accepted |
| 008 | [Multi-provider monitoring matrix](008-multi-provider-monitoring.md) | Accepted |
| 009 | [Dual networking stack (Ingress + Gateway API)](009-dual-networking-stack.md) | Accepted |
| 010 | [Argo CD sync-waves baked in by default](010-argocd-sync-waves.md) | Accepted |
| 011 | [Standard-wins labels and invariant workload selectors](011-standard-wins-labels-and-invariant-selectors.md) | Accepted |
| 012 | [Pod-spec hashing for Job idempotency](012-job-spec-hashing-for-idempotency.md) | Accepted |
| 013 | [Schema-driven validation, not template-side](013-schema-driven-validation.md) | Accepted |
| 014 | [Deterministic ordering of map-iterated collections](014-deterministic-ordering.md) | Accepted |
| 015 | [ESO `data` vs `dataFrom` and chart-vs-external disambiguation](015-eso-data-vs-datafrom.md) | Accepted |
| 016 | [Metrics port auto-exposure on Service](016-metrics-port-auto-exposure.md) | Accepted |
| 017 | [Reloader annotation injection](017-reloader-annotation-injection.md) | Accepted |
| 018 | [Testing with `helm-unittest` and fixtures](018-testing-with-helm-unittest.md) | Accepted |
| 019 | [Pre-fill API-server defaults on atomic list fields](019-explicit-atomic-list-defaults.md) | Accepted |
| 020 | [`tpl`-evaluated hostnames and parentRefs](020-tpl-hostnames-and-parentrefs.md) | Accepted |

## Template

```markdown
# NNN — Title

- **Status:** Accepted | Superseded by NNN | Deprecated
- **Date:** YYYY-MM-DD

## Context
What forces are at play. Constraints from Kubernetes, GitOps tools, the chart's universal scope, prior incidents.

## Decision
The choice we made, in one paragraph.

## Consequences
What this enables, what it costs, what it forecloses. Migration notes if it replaced a previous approach.

## Alternatives considered
Brief — one or two lines each.

## References
Value paths (e.g. `integrations.monitoring.defaults.exposeService`), helper names, named blocks in `values.yaml`, related ADRs. **Avoid line numbers** in any file reference — they rot the moment someone reformats the file. Avoid commit SHAs for the same reason — git history is the authoritative timeline.
```
