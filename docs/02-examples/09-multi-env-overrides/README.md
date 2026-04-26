# 09 — Base values + per-env overrides (dev / staging / prod)

One chart, one app — three environments. The values are split into a `values-base.yaml` carrying the invariant configuration and three thin `values-<env>.yaml` overlays that adjust replica counts, resource sizing, image tags and a few env vars.

This shows how the chart's keyed-map structure ([ADR 002](../../05-adr/002-multi-workload-keyed-maps.md)) and `global.env` cascade ([ADR 003](../../05-adr/003-layered-inheritance-and-override.md)) make per-environment overlays minimal — typically 10-20 lines each.

## Files (different shape than other examples)

| File | Purpose |
|------|---------|
| [`values-base.yaml`](values-base.yaml) | Common configuration applied to every environment. |
| [`values-dev.yaml`](values-dev.yaml) | Dev overrides: 1 replica, smaller resources, `dev` image tag. |
| [`values-staging.yaml`](values-staging.yaml) | Staging overrides: 2 replicas, prod-ish sizing, staging hostname. |
| [`values-prod.yaml`](values-prod.yaml) | Prod overrides: HPA on, real resources, real hostname, monitoring on. |
| [`argocd/application-prod.yaml`](argocd/application-prod.yaml) | Argo CD `Application` for prod, multi-source: chart + base + prod overlay. |
| [`argocd/applicationset.yaml`](argocd/applicationset.yaml) | One Argo CD `ApplicationSet` rendering one Application per environment from a list generator. |
| [`flux/ocirepository.yaml`](flux/ocirepository.yaml) | Flux `OCIRepository`. |
| [`flux/helmrelease-prod.yaml`](flux/helmrelease-prod.yaml) | Flux `HelmRelease` for prod, with `valuesFrom` referencing a ConfigMap + inline overlay. |
| [`helm/install-dev.sh`](helm/install-dev.sh) | Plain `helm upgrade --install` for dev (`-f values-base.yaml -f values-dev.yaml`). |

## What this shows

- **Two-file values pattern**: pass `values-base.yaml` and `values-<env>.yaml` to Helm via repeated `-f`. Later files win on key collision.
- **Argo CD multi-source with multiple `valueFiles`**: the chart source lists both files; Argo CD merges them in order before running Helm.
- **Argo CD `ApplicationSet`**: a list generator declares the envs once; the template stamps out an Application per env. Avoids hand-maintaining three near-identical Application CRs.
- **Flux `valuesFrom`**: prod values can also live in a ConfigMap (managed separately) — useful when ops change values out-of-band of git.

## Try it (dev only — adjust for other envs)

```bash
# Helm
bash helm/install-dev.sh

# Argo CD (prod)
kubectl apply -f argocd/application-prod.yaml -n argocd

# Argo CD (all three envs at once)
kubectl apply -f argocd/applicationset.yaml -n argocd

# Flux (prod)
kubectl apply -f flux/
```

## Related ADRs

- [ADR 002 — Multi-workload via keyed maps](../../05-adr/002-multi-workload-keyed-maps.md)
- [ADR 003 — Layered inheritance and override](../../05-adr/003-layered-inheritance-and-override.md)
