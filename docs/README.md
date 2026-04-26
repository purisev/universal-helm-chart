# Documentation

`universal-helm-chart` is one Helm chart that covers the common Kubernetes workload shapes — Deployments, StatefulSets, Jobs, CronJobs — along with the networking, autoscaling, monitoring, secrets and policy resources that almost every release ends up needing. The goal is to keep one well-tested template in one place so individual services don't each carry a pile of YAML.

These docs are versioned with the chart and **never ship inside the OCI artifact** (see [`.helmignore`](../.helmignore)).

## Where to start

| You want to… | Read |
|--------------|------|
| Understand what this chart does and why it's shaped that way | [`01-getting-started/`](01-getting-started/) |
| Copy a working example | [`02-examples/`](02-examples/) |
| Look up a `values.yaml` field | [`03-reference/`](03-reference/) |
| Hack on the chart itself | [`04-contributing/`](04-contributing/) |
| Read the design decision behind a feature | [`05-adr/`](05-adr/) |

## Sections

- [`01-getting-started/`](01-getting-started/) — concepts, install, quickstart.
- [`02-examples/`](02-examples/) — self-contained scenarios. Each example is a folder you can copy verbatim. Every example carries its own `values.yaml` plus ready-to-apply manifests for **Argo CD** (single-source and multi-source `sources[]`), **Flux** (`OCIRepository` + `HelmRelease`) and plain **`helm` CLI**.
- [`03-reference/`](03-reference/) — `values.yaml` reference, schema notes, version compatibility.
- [`04-contributing/`](04-contributing/) — local dev, testing, releases.
- [`05-adr/`](05-adr/) — Architecture Decision Records. Numbered by importance: `001` is the most foundational decision, the tail covers narrower refinements.

## Conventions

- Top-level sections and concrete examples use numeric prefixes (`01-`, `02-`, …) so file-system order matches reading order.
- ADR files use a three-digit prefix (`001-…`).
- Examples follow a fixed shape: `README.md`, `values.yaml`, `argocd/`, `flux/`, `helm/`. The kitchen-sink example (`99-kitchen-sink/`) intentionally exercises everything at once.
- All documentation is in English.
