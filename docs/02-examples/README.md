# Examples

Self-contained scenarios. **Each folder is a copy-and-deploy unit.** The shape is identical everywhere:

```text
NN-name/
├── README.md                       # what this shows; delta vs. previous example
├── values.yaml                     # the chart values for this scenario
├── argocd/
│   ├── application.yaml            # single-source: chart from oci://ghcr.io/purisev
│   └── application-multisource.yaml    # spec.sources[]: chart from OCI + values from a git repo via $values
├── flux/
│   ├── ocirepository.yaml          # FluxCD OCIRepository pointing at the OCI chart
│   └── helmrelease.yaml            # HelmRelease consuming the OCIRepository
└── helm/
    └── install.sh                  # plain helm install / upgrade --install command
```

Numbering encodes complexity: `01` is the smallest possible deploy, `99` shows everything at once.

> Note: `09-multi-env-overrides/` deliberately breaks the fixed shape — it ships multiple `values-<env>.yaml` files plus environment-specific Argo CD / Flux manifests. See its own README.

## Catalog

| #   | Folder | Demonstrates |
|-----|--------|--------------|
| 01  | [`01-minimal/`](01-minimal/) | Deployment + Service, smallest possible values |
| 02  | [`02-web-app-ingress/`](02-web-app-ingress/) | Deployment + Service + Ingress + HPA + ServiceMonitor |
| 03  | [`03-statefulset-pvc/`](03-statefulset-pvc/) | 3-replica StatefulSet with per-pod PVC, headless Service, PDB |
| 04  | [`04-gateway-api/`](04-gateway-api/) | HTTPRoute with per-workload route shorthand + cross-namespace ReferenceGrant |
| 05  | [`05-cronjobs/`](05-cronjobs/) | `jobGroups` — Job (PreSync hook, tasks-mode) + CronJob (two scheduled jobs) |
| 06  | [`06-monitoring/`](06-monitoring/) | ServiceMonitor + PodMonitor + annotations-mode + per-workload provider override (VM) |
| 07  | [`07-external-secrets/`](07-external-secrets/) | ESO `SecretStore` (Vault) + `ExternalSecret` (`data` and `dataFrom`) + Reloader |
| 08  | [`08-keda-event-driven/`](08-keda-event-driven/) | KEDA `ScaledObject` (Kafka lag trigger) + VPA Initial mode (orthogonal) |
| 09  | [`09-multi-env-overrides/`](09-multi-env-overrides/) | Base values + per-env overlays + Argo CD `ApplicationSet` + Flux `valuesFrom` |
| 10  | [`10-init-containers/`](10-init-containers/) | Per-workload `initContainers` map — wait-for-db + schema migration before the main container starts |
| 99  | [`99-kitchen-sink/`](99-kitchen-sink/) | Everything-on showcase |

## Picking an example

- Brand new to the chart → `01-minimal`.
- Web service that needs to be reachable from outside the cluster → `02-web-app-ingress`.
- Stateful workload with persistent storage → `03-statefulset-pvc`.
- Migrating from Ingress to Gateway API → `04-gateway-api`.
- Schema migrations or scheduled tasks → `05-cronjobs`.
- Wiring up scrape targets → `06-monitoring`.
- Pulling secrets from Vault / AWS / GCP → `07-external-secrets`.
- Event-driven worker scaling → `08-keda-event-driven`.
- Same app in dev / staging / prod → `09-multi-env-overrides`.
- Init containers for wait-for-X / one-shot bootstrap before the main app → `10-init-containers`.
- All the bells and whistles → `99-kitchen-sink`.
