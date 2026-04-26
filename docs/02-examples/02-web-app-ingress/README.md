# 02 — web app with Ingress and HPA

A web service reachable from outside the cluster, scaling on CPU.

## What this shows

- One Deployment with a multi-port Service (`http` + `metrics`).
- Singleton `ingress` block with one host and one TLS secret.
- HPA on CPU.
- Monitoring via ServiceMonitor (Prometheus Operator), targeting the `metrics` port by name.
- A pod-level `securityContext` and resource requests / limits.

## Delta from `01-minimal`

| Added | What changed |
|-------|--------------|
| `service.ports` (map) | Replaces single-port `service.port` shorthand to expose two ports. |
| `metrics.enabled: true` | Opt-in to monitoring (defaults are off). |
| `ingress` | Routes `web.example.com` to the Service. |
| `hpa` | Auto-scales on CPU; `replicaCount` is omitted from the rendered Deployment because HPA is on (see [ADR 007](../../05-adr/007-autoscaler-mutual-exclusion.md)). |
| `integrations.monitoring.defaults.enabled: true` | Turns the default scrape on for every workload (per-workload `metrics.enabled` still acts as opt-out). |

## Files

| File | Purpose |
|------|---------|
| [`values.yaml`](values.yaml) | Chart values for this scenario. |
| [`argocd/application.yaml`](argocd/application.yaml) | Argo CD `Application`, single source. |
| [`argocd/application-multisource.yaml`](argocd/application-multisource.yaml) | Argo CD `Application` with `spec.sources[]`. |
| [`flux/ocirepository.yaml`](flux/ocirepository.yaml) | Flux `OCIRepository`. |
| [`flux/helmrelease.yaml`](flux/helmrelease.yaml) | Flux `HelmRelease`. |
| [`helm/install.sh`](helm/install.sh) | Plain `helm upgrade --install` command. |

## Try it

```bash
# Helm
bash helm/install.sh

# Argo CD
kubectl apply -f argocd/application.yaml -n argocd

# Flux
kubectl apply -f flux/
```

## Prerequisites

- An Ingress controller (e.g. `nginx`, `traefik`) installed in the cluster. Adjust `ingressClassName`.
- Prometheus Operator CRDs (`monitoring.coreos.com`) installed if you want the ServiceMonitor to actually be picked up. Without them the chart still renders but the resource has no consumer.
- For TLS to work, a Secret named `web-example-tls` with cert/key, or a cert-manager `Certificate` issuing into it.
