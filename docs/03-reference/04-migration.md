# Migration

What changes between releases that may require values-file edits when you upgrade. The chart's value surface is intentionally large; most edits are additive, but a few iterations on the `release-2.0.0` line tightened the schema in ways that turn previously-silent no-ops into render-time errors. Most of the changes below reject values that never had any rendered effect; the **63-char enforcement** (last section) is the exception — it can additionally reject values that previously rendered a working manifest whose constructed name was too long to be reused as the `app.kubernetes.io/instance` label value the chart sets on the same resource.

## 2.0.0

### Per-workload `httpRoute` / `grpcRoute` / `tlsRoute` accept only `enabled`, `priority`, `rules`

The chart's HTTPRoute / GRPCRoute / TLSRoute model is one route resource per release: `parentRefs`, `hostnames`, `annotations`, and `metadataAnnotations` live on the **singleton** root entry (`.Values.httpRoute.*`) or on a named entry under the **plural map** (`.Values.httpRoutes.<name>.*`), and the per-workload entries (`deployments.<wl>.httpRoute`, `statefulSets.<wl>.httpRoute`, and the gRPC / TLS equivalents) contribute only their `rules` to the merged singleton.

Pre-2.0.0 the schema reused the full route shape at the per-workload level too, accepting `parentRefs` / `hostnames` / `annotations` / `metadataAnnotations` and silently dropping them at render time. The schema now rejects those fields on per-workload entries with `additional properties '<field>' not allowed`.

**If your values fail validation,** move the affected fields up:

```yaml
# Before — schema-rejected on a per-workload route:
deployments:
  web:
    httpRoute:
      enabled: true
      priority: 10
      parentRefs:
        - name: my-gateway
          namespace: gateway-ns
      hostnames:
        - api.example.com
      rules:
        - matches: [...]

# After — parentRefs / hostnames live on the singleton, shared across every
# workload that contributes rules:
httpRoute:
  enabled: true
  parentRefs:
    - name: my-gateway
      namespace: gateway-ns
  hostnames:
    - api.example.com

deployments:
  web:
    httpRoute:
      enabled: true
      priority: 10
      rules:
        - matches: [...]
```

If you genuinely need different `parentRefs` or `hostnames` per workload, declare a separate route under the plural map (`httpRoutes.<name>`) — that entry takes the full route shape (and is itself rendered as its own HTTPRoute resource named `<release>-<name>`).

### 63-char enforcement on constructed names and label values

Before this release, a long Helm release name combined with a long workload key could produce a value past Kubernetes' 63-char DNS-1123 label limit. For some kinds — label values themselves, and Service names — Kubernetes rejected the manifest at admission with a generic error that didn't point at the offending values key. For others — ConfigMap, Deployment, and friends, where the metadata.name is allowed up to 253 chars as a DNS-1123 subdomain — the manifest applied, but the resource ended up with a name the chart couldn't reuse as its own `app.kubernetes.io/instance` label value, so selector lookups and label-based queries against the resource silently broke.

The chart now fails fast at `helm template` time with a precise error naming the kind, the offending value, its length, and the values keys to shorten (Helm release name, `.Values.fullnameOverride`, or the workload / entry key). This is **stricter than Kubernetes** for the second category above — a values file that previously rendered a working ConfigMap or Deployment whose name exceeded 63 chars is now rejected, on the grounds that the chart's own labelling contract is the one that matters.

**If you hit this**, shorten one of:

- The Helm release name — `helm install --name <shorter>` / Argo CD `metadata.name` on the `Application`.
- `.Values.fullnameOverride` — overrides `<release>-<chart>` with whatever you set.
- The workload key under `deployments` / `statefulSets` / `configMaps` / `jobGroups` / `httpRoutes` / etc.

The chart enforces 63 across **every** constructed name (not only Service names — even ConfigMap and Deployment names, which Kubernetes allows up to 253 chars) so the value remains usable as the `app.kubernetes.io/instance` label on the same workload.

### Other tightenings worth knowing about

The schema also closes a number of previously-permissive shapes (`additionalProperties: false` on every chart-defined object, drop of fields the chart never rendered like `statefulSets.<name>.progressDeadlineSeconds`, fail-fast for `headlessService.enabled: false` without `serviceName`, fail-fast for `rbac.enabled` without `serviceAccount.create`). If your values predate the round-by-round polish on the `release-2.0.0` branch and validation now rejects them, the message names the offending key and the right shape.
