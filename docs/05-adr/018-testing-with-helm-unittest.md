# 018 — Testing with `helm-unittest` and fixtures

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

The chart's blast radius is wide: a one-character helper edit lands on every consumer at next upgrade. We need a regression suite that:

- runs in CI on every PR and is fast enough to run before commit too;
- catches subtle template bugs (a missing field, a wrong sort key, a label drift);
- is readable enough that a contributor adding a feature can write the test without reverse-engineering a framework;
- doesn't require a real Kubernetes cluster.

The Helm ecosystem has two main options:

- **`helm-unittest`** — a Helm plugin that runs YAML-defined test suites against the rendered chart. Tests live next to the chart in `tests/`. Asserts on rendered manifests via `equal`, `matchRegex`, `isKind`, `notExists`, etc. Supports snapshot tests.
- **`chart-testing` (`ct`)** + a real cluster — installs the chart into kind / minikube and asserts via `kubectl`. Heavier; useful for integration tests but overkill for shape regressions.

## Decision

Use **`helm-unittest`** as the chart's primary test framework. Tests live in `tests/`, fixtures in `tests/fixtures/`, snapshots (when used) in `tests/__snapshot__/`.

**Conventions:**

- **One test suite per template.** `tests/deployment_test.yaml` covers `templates/deployment.yaml`; `tests/job_groups_test.yaml` covers `templates/job-groups.yaml`. Cross-cutting features (e.g. metrics annotations, integrations) get their own files (`tests/metrics_annotations_test.yaml`, `tests/integrations_test.yaml`).
- **Prefer assertion tests over snapshots.** Assertions are descriptive (`isKind: Deployment`, `equal: spec.replicas: 3`); they survive harmless renames in unrelated parts of the manifest. Snapshots are byte-for-byte and break loudly on any whitespace change. We use snapshots only where the rendered output is a complex multi-document YAML and asserting field-by-field would be tedious — currently no snapshot fixtures exist (`tests/__snapshot__/` is empty).
- **Fixtures for non-trivial inputs.** A test asserting that `service.ports` renders in http-first / metrics-last order (see [ADR 014](014-deterministic-ordering.md)) reads a `set:` block from `tests/fixtures/service-multiport.yaml` rather than inlining 30 lines of YAML. Each fixture has a focused purpose; the file name describes it (`es-datafrom-auto.yaml`, `commonlabels-conflict.yaml`).
- **Test against the schema too.** `helm-unittest` runs Helm's schema validation as part of rendering. A test case that violates `values.schema.json` fails the suite — this catches schema regressions.
- **Negative tests are valuable.** "This combination should fail" asserts via `expectFail` confirm fail-fast guards (HPA + KEDA, jobGroups hash + delete policy) actually fire.

The CI workflow at `.github/workflows/ci.yaml` runs `helm lint` then `helm unittest .`. The release workflow at `.github/workflows/release.yaml` runs the same checks before pushing the OCI artifact.

## Consequences

**What this enables:**

- A new feature lands with tests. PR reviewers can run `helm unittest .` locally in seconds.
- The fixture catalogue serves as **executable documentation**: reading `tests/fixtures/keda-deployment.yaml` shows a working KEDA + Deployment combination quicker than reading the docs.
- Regressions are caught before merge. The `_helpers.tpl` is dense; tests are the only practical safety net.

**What it costs:**

- `helm-unittest` is a plugin, not part of upstream Helm. Contributors install it once (`helm plugin install https://github.com/helm-unittest/helm-unittest --verify=false`); CI does the same.
- Test files are large (`tests/deployment_test.yaml` is ~34 KB). Discoverability suffers when one suite covers many cases; we mitigate by ordering test cases by feature (replicas, env, volumes, sidecars, …) and using descriptive `it:` titles.
- Snapshot tests, when added, will need a clear "regenerate snapshot" runbook. Until we have one, prefer assertion tests.

## What makes a good fixture

A good fixture in `tests/fixtures/`:

- Has a single, narrow purpose. `es-datafrom-auto.yaml` shows ESO `dataFrom` auto-derivation, nothing else.
- Names the purpose in the file name. A reviewer reading a test that loads `commonlabels-conflict.yaml` immediately knows what's being tested.
- Stays minimal. The fewer values it sets, the less work a future change to the chart does to keep it valid.
- Is loaded via `set:` blocks that point at the fixture; the test asserts on the rendered output, not the fixture itself.

## Alternatives considered

- **`chart-testing` against kind.** Rejected as the primary suite: too slow, too much infrastructure for shape-regression coverage. May add later as a thin smoke-test layer.
- **Pytest + `helm template` in a subprocess.** Rejected: re-implements what `helm-unittest` already does, with worse readability for chart authors.
- **Snapshots for everything.** Rejected: a label rename touches every snapshot and produces noisy PRs that hide signal.
- **No tests; rely on review.** Rejected; obviously.

## References

- `tests/` — all test suites
- `tests/fixtures/` — focused inputs
- `tests/__snapshot__/` — snapshot directory (currently empty)
- `.github/workflows/ci.yaml`, `.github/workflows/release.yaml` — CI pipelines
- `helm-unittest`: https://github.com/helm-unittest/helm-unittest
- Related: [ADR 013](013-schema-driven-validation.md) (schema validation runs as part of unittest)
