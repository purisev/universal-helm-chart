# Compatibility

Versions and APIs the chart targets. The intent here is to be honest about **what the chart renders** rather than to claim a tested SemVer matrix that rots on every operator release.

## Helm

- **3.8+** — required for OCI registries (`oci://ghcr.io/...`).
- **3.14+** — recommended; brings the latest schema-validation features used by `values.schema.json` (draft 2020-12 keywords).

## Kubernetes APIs the chart renders

The chart emits resources from these stable API groups:

| Resource | API group / version |
|----------|--------------------|
| Deployment, StatefulSet | `apps/v1` |
| Job, CronJob | `batch/v1` |
| HorizontalPodAutoscaler | `autoscaling/v2` |
| Service, ServiceAccount, ConfigMap | `v1` |
| Ingress, NetworkPolicy | `networking.k8s.io/v1` |
| Role, RoleBinding | `rbac.authorization.k8s.io/v1` |
| PodDisruptionBudget | `policy/v1` |

**Implied minimum cluster:** Kubernetes **1.21+**. That's the release where `batch/v1` `CronJob` graduated to GA; everything else the chart uses has been stable longer. The chart is exercised against the two latest stable Kubernetes versions in CI.

## Optional CRDs (per integration)

Each integration is opt-in; install only the CRDs for the integrations you enable.

| Feature | API group / version chart renders |
|---------|-----------------------------------|
| Gateway API routes — HTTPRoute, GRPCRoute, TLSRoute | `gateway.networking.k8s.io/v1` |
| Gateway API ReferenceGrant | `gateway.networking.k8s.io/v1beta1` |
| External Secrets Operator | `external-secrets.io/v1` (auto-detects `v1beta1` fallback via `.Capabilities`) |
| KEDA `ScaledObject` | `keda.sh/v1alpha1` |
| Prometheus Operator monitors — ServiceMonitor, PodMonitor | `monitoring.coreos.com/v1` |
| VictoriaMetrics scrapes — VMServiceScrape, VMPodScrape | `operator.victoriametrics.com/v1beta1` |
| Vertical Pod Autoscaler | `autoscaling.k8s.io/v1` |
| Argo CD Image Updater | `argocd-image-updater.argoproj.io/v1alpha1` |

Stakater Reloader is annotation-driven — no CRDs to install on its side; just the Reloader controller in the cluster.

## Tested with

The chart renders against the **current stable release** of each operator. The auto-detection paths (`.Capabilities.APIVersions.Has`) handle the common transition windows between operator API versions. Open an issue if you find an incompatibility on an older or pre-release version — we'll patch the detection.

## Outside the chart

The chart **doesn't** ship the operators themselves. That's deliberate: a universal chart shouldn't take a dependency on a specific Prometheus / VictoriaMetrics / KEDA / ESO release line. Install operators with their own published charts, then turn the matching `integrations.<name>.enabled` switch on.
