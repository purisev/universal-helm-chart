# 01 — minimal

The smallest possible deploy: one Deployment running an `nginx` image, exposing port 80 via a ClusterIP Service. No Ingress, no monitoring, no secrets, no autoscaling.

## What this shows

- One workload declared under `deployments.web`.
- The single-port Service shorthand (`service.port` / `service.targetPort` rather than the `service.ports` map).
- The opt-in default for everything else: monitoring off, autoscaling off, RBAC off.

## Files

| File | Purpose |
|------|---------|
| [`values.yaml`](values.yaml) | Chart values for this scenario. |
| [`argocd/application.yaml`](argocd/application.yaml) | Argo CD `Application`, single source. |
| [`argocd/application-multisource.yaml`](argocd/application-multisource.yaml) | Argo CD `Application` with `spec.sources[]` — chart from OCI, values from a git repo via `$values`. |
| [`flux/ocirepository.yaml`](flux/ocirepository.yaml) | Flux `OCIRepository` pointing at the OCI chart. |
| [`flux/helmrelease.yaml`](flux/helmrelease.yaml) | Flux `HelmRelease` consuming the `OCIRepository`. |
| [`helm/install.sh`](helm/install.sh) | Plain `helm upgrade --install` command. |

## Try it

Pick any one of:

- **Helm CLI:** `bash helm/install.sh`
- **Argo CD:** `kubectl apply -f argocd/application.yaml -n argocd`
- **Flux:** `kubectl apply -f flux/`
