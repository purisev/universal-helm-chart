# 07 — External Secrets Operator + Reloader

A web app whose database password and API tokens are synced from HashiCorp Vault by ESO. When Vault rotates the secret, ESO updates the Kubernetes Secret, and Reloader bounces the Deployment to pick up the change.

## What this shows

- `integrations.eso.secretStores.vault` — a `SecretStore` resource targeting Vault via JWT auth.
- `integrations.eso.externalSecrets.app-secrets` — an `ExternalSecret` with explicit per-key `data` mapping. Each entry maps a remote key + property to a field in the resulting K8s Secret.
- `integrations.eso.externalSecrets.bulk-config` — a second `ExternalSecret` using `dataFrom` (bulk extraction): every field in the remote secret lands in the K8s Secret.
- `integrations.stakater.reloader.enabled: true` — when ESO writes a new K8s Secret, Reloader auto-restarts the Deployment.
- The Deployment consumes both secrets via `envSecrets` — the standard chart pattern.
- `serviceAccount.create: true` — required for Vault JWT auth (the SA token is what Vault validates).

## Delta from `02-web-app-ingress`

| Changed | What |
|---------|------|
| `integrations.eso` | New: `secretStores` + `externalSecrets` blocks. |
| `integrations.stakater.reloader.enabled: true` | Auto-restart on Secret/CM change. |
| `serviceAccount.create: true` | Required for ESO JWT auth via SA token. |
| `envSecrets` | Now references the ESO-generated Secrets, not externally-created ones. |

## Files

| File | Purpose |
|------|---------|
| [`values.yaml`](values.yaml) | Chart values. |
| [`argocd/application.yaml`](argocd/application.yaml) | Argo CD `Application`, single source. |
| [`argocd/application-multisource.yaml`](argocd/application-multisource.yaml) | Argo CD `Application` with `spec.sources[]`. |
| [`flux/ocirepository.yaml`](flux/ocirepository.yaml) | Flux `OCIRepository`. |
| [`flux/helmrelease.yaml`](flux/helmrelease.yaml) | Flux `HelmRelease`. |
| [`helm/install.sh`](helm/install.sh) | Plain `helm upgrade --install`. |

## Try it

```bash
bash helm/install.sh
kubectl apply -f argocd/application.yaml -n argocd
kubectl apply -f flux/
```

## Prerequisites

- External Secrets Operator installed (`external-secrets.io` CRDs).
- Stakater Reloader installed (or remove `integrations.stakater.reloader` from the values).
- A reachable Vault server with JWT auth method enabled, role `eso-app` allowed, and the secrets present at `secret/data/app/...`.
- The `app-vault` SecretStore JWT mount path matches Vault's `auth/jwt` configuration.

## Related ADRs

- [ADR 015 — ESO `data` vs `dataFrom`](../../05-adr/015-eso-data-vs-datafrom.md)
- [ADR 017 — Reloader annotation injection](../../05-adr/017-reloader-annotation-injection.md)
- [ADR 006 — `integrations` namespace](../../05-adr/006-integrations-namespace.md)
