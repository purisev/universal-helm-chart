# Summary

[Introduction](README.md)

# Getting started

- [Overview](01-getting-started/README.md)
  - [Concepts](01-getting-started/01-concepts.md)
  - [Installation](01-getting-started/02-installation.md)
  - [Quickstart](01-getting-started/03-quickstart.md)

# Examples

- [Overview](02-examples/README.md)
  - [01 — minimal](02-examples/01-minimal/README.md)
  - [02 — web app with Ingress and HPA](02-examples/02-web-app-ingress/README.md)
  - [03 — StatefulSet with PVC and headless Service](02-examples/03-statefulset-pvc/README.md)
  - [04 — Gateway API with cross-namespace ReferenceGrant](02-examples/04-gateway-api/README.md)
  - [05 — jobGroups (Job + CronJob)](02-examples/05-cronjobs/README.md)
  - [06 — Monitoring (Prometheus + VictoriaMetrics, Service + Pod targets)](02-examples/06-monitoring/README.md)
  - [07 — External Secrets Operator + Reloader](02-examples/07-external-secrets/README.md)
  - [08 — KEDA event-driven autoscaling](02-examples/08-keda-event-driven/README.md)
  - [09 — Base values + per-env overrides (dev / staging / prod)](02-examples/09-multi-env-overrides/README.md)
  - [10 — init containers](02-examples/10-init-containers/README.md)
  - [99 — kitchen sink](02-examples/99-kitchen-sink/README.md)

# Reference

- [Overview](03-reference/README.md)
  - [Values reference](03-reference/01-values.md)
  - [Schema and IDE setup](03-reference/02-schema.md)
  - [Compatibility](03-reference/03-compatibility.md)
  - [Migration](03-reference/04-migration.md)

# Contributing

- [Overview](04-contributing/README.md)
  - [Development](04-contributing/01-development.md)
  - [Testing](04-contributing/02-testing.md)
  - [E2E testing](04-contributing/03-e2e-testing.md)
  - [Releasing](04-contributing/04-releasing.md)

# Architecture Decision Records

- [Overview](05-adr/README.md)
  - [001 — Universal chart: one chart for all common workloads](05-adr/001-universal-chart-scope.md)
  - [002 — Multi-workload via keyed maps in a single release](05-adr/002-multi-workload-keyed-maps.md)
  - [003 — Layered inheritance and explicit override](05-adr/003-layered-inheritance-and-override.md)
  - [004 — Maps over lists as the default collection shape](05-adr/004-maps-over-lists.md)
  - [005 — jobGroups unifying Job and CronJob](05-adr/005-jobgroups-unification.md)
  - [006 — integrations namespace for ecosystem knobs](05-adr/006-integrations-namespace.md)
  - [007 — Autoscaler mutual exclusion (HPA / KEDA / VPA)](05-adr/007-autoscaler-mutual-exclusion.md)
  - [008 — Multi-provider monitoring matrix](05-adr/008-multi-provider-monitoring.md)
  - [009 — Dual networking stack (Ingress + Gateway API)](05-adr/009-dual-networking-stack.md)
  - [010 — Argo CD sync-waves baked in by default](05-adr/010-argocd-sync-waves.md)
  - [011 — Standard-wins labels and invariant workload selectors](05-adr/011-standard-wins-labels-and-invariant-selectors.md)
  - [012 — Pod-spec hashing for Job idempotency under GitOps](05-adr/012-job-spec-hashing-for-idempotency.md)
  - [013 — Schema-driven validation, not template-side](05-adr/013-schema-driven-validation.md)
  - [014 — Deterministic ordering of map-iterated collections](05-adr/014-deterministic-ordering.md)
  - [015 — ESO data vs dataFrom and chart-vs-external disambiguation](05-adr/015-eso-data-vs-datafrom.md)
  - [016 — Metrics port auto-exposure on Service](05-adr/016-metrics-port-auto-exposure.md)
  - [017 — Reloader annotation injection](05-adr/017-reloader-annotation-injection.md)
  - [018 — Testing with helm-unittest and fixtures](05-adr/018-testing-with-helm-unittest.md)
