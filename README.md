# universal-helm-chart

A single Helm chart that covers the common Kubernetes workload shapes — Deployments, StatefulSets, Jobs and CronJobs — together with the networking, autoscaling, monitoring, secrets and policy resources that almost every release ends up needing. One template, one place to fix bugs, one place to roll out fleet-wide defaults.

Published as an OCI artifact at `oci://ghcr.io/purisev/universal-helm-chart`.

## Quick install

```bash
helm upgrade --install my-app \
  oci://ghcr.io/purisev/universal-helm-chart \
  --version 3.0.0 \
  -f values.yaml
```

The smallest viable `values.yaml`:

```yaml
deployments:
  api:
    image:
      repository: nginx
      tag: "1.27"
    service:
      ports:
        http:
          port: 80
```

## Documentation

Full documentation lives under [`docs/`](docs/) (not shipped in the OCI artifact). Start at [`docs/README.md`](docs/README.md):

- [`docs/01-getting-started/`](docs/01-getting-started/) — concepts, install, quickstart.
- [`docs/02-examples/`](docs/02-examples/) — copy-and-deploy scenarios. Each example carries its own `values.yaml` plus ready-to-apply manifests for **Argo CD** (single-source and multi-source `sources[]`), **Flux** (`OCIRepository` + `HelmRelease`) and plain **`helm` CLI**.
- [`docs/03-reference/`](docs/03-reference/) — `values.yaml` reference, schema notes, version compatibility.
- [`docs/04-contributing/`](docs/04-contributing/) — local dev, testing, releases.
- [`docs/05-adr/`](docs/05-adr/) — Architecture Decision Records covering why the chart is shaped the way it is.

## Feedback and contributing

Bug reports and feature requests go through [GitHub Issues](https://github.com/purisev/universal-helm-chart/issues). Security vulnerabilities go through [private vulnerability reporting](https://github.com/purisev/universal-helm-chart/security/advisories/new) instead, per [`SECURITY.md`](SECURITY.md). For contributing changes, start at [`docs/04-contributing/`](docs/04-contributing/).

## License

Apache-2.0 — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
