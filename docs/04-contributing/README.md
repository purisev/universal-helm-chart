# Contributing

Four short reads, in order. The whole section is intentionally lean — a first-time contributor should be able to skim it in five minutes (the e2e page is the exception; skim its job table, come back when you're adding a live-cluster scenario).

- [`01-development.md`](01-development.md) — prerequisites, clone-and-verify, dev loop, common pitfalls.
- [`02-testing.md`](02-testing.md) — `helm-unittest` cookbook: two patterns, the asserts you need, three steps to add a test.
- [`03-e2e-testing.md`](03-e2e-testing.md) — label-gated live-cluster suite: what each job covers, how to run one locally, how to add a scenario.
- [`04-releasing.md`](04-releasing.md) — tag, push, CI publishes to `oci://ghcr.io/purisev`.

The chart's design rationale lives in [`../05-adr/`](../05-adr/) — read those before proposing changes that affect `values.yaml` shape.
