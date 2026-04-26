# Testing

The chart's regression suite uses [`helm-unittest`](https://github.com/helm-unittest/helm-unittest). This page is the practical cookbook; for the design rationale see [ADR 018](../05-adr/018-testing-with-helm-unittest.md).

## Layout

- One suite per template: `tests/<template>_test.yaml` covers `templates/<template>.yaml`.
- Shared values blocks live in `tests/fixtures/`. Use a fixture when the same `set:` block would repeat across two or more tests, or when the values block exceeds ~10 lines.

Run the full suite:

```bash
helm unittest .
```

## Two patterns — pick one per test

**Inline `set:`** for short cases:

```yaml
- it: should render Service when enabled
  set:
    image.repository: nginx
    image.tag: alpine
    deployments.web.enabled: true
    deployments.web.service.enabled: true
    deployments.web.service.port: 80
  asserts:
    - isKind:
        of: Service
```

**Fixture file** for non-trivial inputs:

```yaml
- it: should render KEDA ScaledObject for the worker
  values:
    - fixtures/keda-deployment.yaml
  asserts:
    - isKind:
        of: ScaledObject
    - matchRegex:
        path: metadata.name
        pattern: -worker$
```

## The asserts you'll need

```yaml
# Verify the rendered kind
- isKind:
    of: Deployment

# Exact field value
- equal:
    path: spec.replicas
    value: 3

# Field shape match
- matchRegex:
    path: spec.template.spec.containers[0].image
    pattern: nginx:.+

# Field absent
- notExists:
    path: spec.replicas
# (or its synonym for null fields)
- isNull:
    path: spec.replicas

# Field present
- isNotNull:
    path: spec.metrics

# Document count in multi-doc render
- hasDocuments:
    count: 2

# Negative test — assert the template fails with a specific message
- failedTemplate:
    errorMessage: "deployments.web: hpa.enabled and keda.enabled are mutually exclusive — both manage spec.replicas. Pick one."
```

## Add a test in three steps

1. **Find the closest existing `it:` block** in the right `tests/<template>_test.yaml`. Copy it.
2. **Tweak `set:`** (or replace it with `values: [fixtures/<name>.yaml]`) to reflect the scenario you're adding. Add or adjust `asserts:` to match the expected output.
3. **Run `helm unittest .`** — green or fix.

CI runs the same command on every PR; tests passing locally is the same signal as CI green.
