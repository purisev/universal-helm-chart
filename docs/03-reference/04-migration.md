# Migration

What changes between releases that may require values-file edits when you upgrade. The chart's value surface is intentionally large; most edits are additive, but a few iterations on the `release-2.0.0` line tightened the schema in ways that turn previously-silent no-ops into render-time errors. Most of the changes below reject values that never had any rendered effect; the **63-char enforcement** (last section) is the exception — it can additionally reject values that previously rendered a working manifest whose constructed name was too long to be reused as the `app.kubernetes.io/instance` label value the chart sets on the same resource.

## 3.0.0

### StatefulSet `service` no longer merges into the headless Service

`statefulSets.<name>.service` always renders as its own, independent Service now. Previously, whenever `headlessService` stayed enabled (the default), `service.*` fields configured the single headless Service object instead of creating a separate one — so a StatefulSet couldn't have a headless Service for stable per-pod DNS *and* a regular client-facing Service at the same time without setting `serviceName` to work around it.

Headless-specific fields moved from `service.*` to `headlessService.*`: `ports`, `annotations`, `publishNotReadyAddresses`, `ipFamilies`, `ipFamilyPolicy`.

```yaml
# Before — service.* configured the headless Service:
statefulSets:
  db:
    service:
      ports:
        db:
          port: 5432
          targetPort: 5432
      annotations:
        example.com/foo: bar

# After — headlessService.* configures the headless Service; service.* now
# always renders a separate, independent client-facing Service and is
# opt-in (set service.enabled: true, or any service.* field, to render it):
statefulSets:
  db:
    headlessService:
      ports:
        db:
          port: 5432
          targetPort: 5432
      annotations:
        example.com/foo: bar
```

`service` also gained the rest of the `ServiceSpec` fields (`externalName`, `loadBalancerSourceRanges`, `sessionAffinityConfig`, `trafficDistribution`, etc.) — `service` only, not `headlessService`: a headless Service has no virtual IP, so the load-balancer, traffic-policy, and session-affinity fields have no meaning there and the schema rejects them.

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

### Name-length enforcement split by resource kind

The chart enforces two different length ceilings depending on how the constructed name is used:

- **63 characters** — applied to Service names and `app.kubernetes.io/instance` label values. Kubernetes DNS-1123 label rules cap both at 63 chars; a name longer than this produces a manifest the API server rejects (for Services) or that breaks selector lookups (for label values).
- **253 characters** — applied to all other chart-constructed names: ConfigMap, Ingress, HTTPRoute, GRPCRoute, TLSRoute, ReferenceGrant, ServiceMonitor, PodMonitor. These are DNS-1123 subdomain names in Kubernetes, which allow up to 253 chars.

The chart fails fast at `helm template` time with a precise error naming the kind, the offending value, its length, and the values keys to shorten (Helm release name, `.Values.fullnameOverride`, or the workload / entry key).

**If you hit a length error**, shorten one of:

- The Helm release name — `helm install --name <shorter>` / Argo CD `metadata.name` on the `Application`.
- `.Values.fullnameOverride` — overrides `<release>-<chart>` with whatever you set.
- The workload key under `deployments` / `statefulSets` / `configMaps` / `jobGroups` / `httpRoutes` / etc.

Names supplied verbatim by the user (`integrations.argocd.imageUpdater.name`, `serviceAccount.name`, ESO `target.name`) are **not** asserted — those are the user's contract with the cluster's DNS limits.

### `metadataAnnotations` dropped from `httpRoute` / `grpcRoute` / `tlsRoute`

Both the singleton (`.Values.httpRoute.metadataAnnotations`) and the plural-map entries (`.Values.httpRoutes.<key>.metadataAnnotations`, and the gRPC / TLS equivalents) accepted a `metadataAnnotations` block that no template ever read. Every route callsite passes `$route.annotations` to the rendered Route's `metadata.annotations`, never `$route.metadataAnnotations`. The schema now rejects the field with `additional properties 'metadataAnnotations' not allowed` — move any values you had under it to the existing `annotations` field (which is the field the rendered Route picks up).

### `ingress.tls` changed from map to native list

`ingress.tls` and per-entry `ingresses.<name>.tls` are now a **native Kubernetes list** instead of a map keyed by secret name. The `secretName` field is optional — omit it for SNI-only TLS routing.

```yaml
# Before (map, secret name as key — schema-rejected):
ingress:
  tls:
    my-tls-secret:
      hosts:
        - example.com

# After (native k8s list):
ingress:
  tls:
    - hosts:
        - example.com
      secretName: my-tls-secret   # optional
```

### `topologySpreadConstraints` changed to native list

The `topologySpreadConstraints` wrapper object (`{enabled, constraints: [...]}`) is removed. The value is now a **native Kubernetes list** directly, at both root and per-workload level.

```yaml
# Before (object wrapper — schema-rejected):
topologySpreadConstraints:
  enabled: true
  constraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: ScheduleAnyway

# After (native k8s list):
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
```

Per-workload override follows the replace-not-concat rule: a workload-level list replaces the root list entirely. Set `topologySpreadConstraints: []` to explicitly disable root constraints on a specific workload.

### `inheritRootSchedParams` removed

The per-workload `inheritRootSchedParams` block (`{affinity, tolerations, tsc}`) is removed. Scheduling field inheritance now follows the universal rule: **workload value replaces root value; omit to inherit; empty value to disable**.

```yaml
# Before:
deployments:
  worker:
    inheritRootSchedParams:
      tolerations: false   # don't inherit root tolerations

# After — set the field explicitly at workload level:
deployments:
  worker:
    tolerations: []        # empty list: no tolerations on this workload
```

### Other tightenings worth knowing about

The schema also closes a number of previously-permissive shapes (`additionalProperties: false` on every chart-defined object, drop of fields the chart never rendered like `statefulSets.<name>.progressDeadlineSeconds`, fail-fast for `headlessService.enabled: false` without `serviceName`, fail-fast for `rbac.enabled` without `serviceAccount.create`). If your values predate the round-by-round polish on the `release-2.0.0` branch and validation now rejects them, the message names the offending key and the right shape.
