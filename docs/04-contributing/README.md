# Contributing

Three short reads, in order. The whole section is intentionally lean — a first-time contributor should be able to skim it in five minutes.

- [`01-development.md`](01-development.md) — prerequisites, clone-and-verify, dev loop, common pitfalls.
- [`02-testing.md`](02-testing.md) — `helm-unittest` cookbook: two patterns, the asserts you need, three steps to add a test.
- [`03-releasing.md`](03-releasing.md) — tag, push, CI publishes to `oci://ghcr.io/purisev`.

The chart's design rationale lives in [`../05-adr/`](../05-adr/) — read those before proposing changes that affect `values.yaml` shape.
