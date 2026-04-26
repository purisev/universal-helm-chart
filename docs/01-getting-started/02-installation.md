# Installation

> Stub — full prose lands in a follow-up PR. Until then, the [`02-examples/01-minimal/`](../02-examples/01-minimal/) folder is enough to install the chart.

## OCI registry

The chart is published to GHCR as an OCI artifact:

```text
oci://ghcr.io/purisev/universal-helm-chart
```

There is no Helm "repo add" step — Helm 3.8+ pulls OCI charts directly:

```bash
helm install my-app oci://ghcr.io/purisev/universal-helm-chart \
  --version 2.0.0 \
  -f values.yaml
```

## Optional CRDs

The chart only renders a resource if you opt in via `values.yaml`. The following CRDs must be installed in the cluster *if and only if* you use the matching feature:

| Feature | CRDs |
|---------|------|
| `integrations.eso` (External Secrets) | `external-secrets.io` |
| `integrations.monitoring` with `provider=prometheus` and `discovery=crd` | `monitoring.coreos.com` (Prometheus Operator) |
| `integrations.monitoring` with `provider=victoriametrics` and `discovery=crd` | `operator.victoriametrics.com` |
| `integrations.keda` autoscalers | `keda.sh` |
| Gateway API routes (`httpRoute` / `grpcRoute` / `tlsRoute` / `referenceGrant`) | `gateway.networking.k8s.io` |
| `verticalPodAutoscaler` | `autoscaling.k8s.io` (VPA) |
| `integrations.argocd.imageUpdater` | `argoproj.io` |

See [`03-reference/03-compatibility.md`](../03-reference/03-compatibility.md) for tested CRD versions.
