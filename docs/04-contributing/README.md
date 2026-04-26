# Contributing

> Stubs in this PR; content fleshed out in follow-ups.

- [`01-development.md`](01-development.md) — local dev loop: `helm template`, `helm-unittest`, fixtures.
- [`02-testing.md`](02-testing.md) — assertion patterns, what makes a good fixture, how to add tests.
- [`03-releasing.md`](03-releasing.md) — CI flow that publishes the chart to GHCR OCI on `v*` tag pushes.

The chart's design rationale lives in [`../05-adr/`](../05-adr/) — read those before proposing changes that affect `values.yaml` shape.
