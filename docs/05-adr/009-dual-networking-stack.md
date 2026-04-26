# 009 — Dual networking stack (Ingress + Gateway API)

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

Two layers of routing primitives are widely deployed in 2025:

- **Ingress** (`networking.k8s.io/v1`) — stable, ubiquitous, controller-specific feature surface (annotations carry the meaning).
- **Gateway API** (`gateway.networking.k8s.io/v1`) — newer, expressive, multi-route-kind: HTTPRoute, GRPCRoute, TLSRoute, plus `ReferenceGrant` for cross-namespace backends.

Real fleets have both: legacy services on Ingress, new services on Gateway API, and migration paths in between. A chart that supports only one forces a hard cutover; a chart that supports both lets each service migrate on its own schedule.

The chart also needs to handle the two reasonable mental models for routing:

- **Per-release routing object** — one Ingress / HTTPRoute per release, every workload contributes rules to it.
- **Per-workload routing object** — each workload owns its own Ingress / HTTPRoute (different controllers, different hostnames, different parents).

## Decision

Support **both** Ingress and Gateway API, with **both** singleton and multi-resource shapes for each:

| Resource         | Singleton key      | Multi-resource map | Templates            |
|------------------|--------------------|--------------------|----------------------|
| Ingress          | `ingress.*`        | `ingresses.*`      | `templates/ingress.yaml` |
| HTTPRoute        | `httpRoute.*`      | `httpRoutes.*`     | `templates/httproute.yaml` |
| GRPCRoute        | `grpcRoute.*`      | `grpcRoutes.*`     | `templates/grpcroute.yaml` |
| TLSRoute         | `tlsRoute.*`       | `tlsRoutes.*`      | `templates/tlsroute.yaml` |
| ReferenceGrant   | `referenceGrant.*` | `referenceGrants.*`| `templates/referencegrant.yaml` |

**Per-workload route shorthand.** When a workload at `deployments.<w>.httpRoute.enabled: true` is set, its rules merge into the **singleton** `httpRoute` (or `grpcRoute` / `tlsRoute`). `parentRefs` and `hostnames` are inherited from the singleton; `serviceName` and `servicePort` default to the workload's Service. A `priority` integer controls rule order in the merged list (lower = earlier; ties broken alphabetically by workload name). The same shorthand works for grpcRoute and tlsRoute.

**ReferenceGrant** lives in the namespace of the *target* (the Service being referenced), so the chart always emits it in the release namespace. It supports cross-namespace HTTPRoute → Service references without RBAC complexity.

**Singleton vs multi-resource.** The singleton exists for the common case (one chart instance, one external entry point). The multi-map exists when the same release exposes routes via different controllers / parents / hostnames (e.g. `nginx-internal` Ingress for east-west traffic, `nginx-external` Ingress for north-south).

## Consequences

**What this enables:**

- A team migrating from Ingress to HTTPRoute can run both side-by-side during the migration window — `ingress.enabled: true` and `httpRoute.enabled: true` co-exist on the same release.
- "Internal + external" Ingresses without a second chart release.
- Cross-namespace Gateway API routing without per-release ReferenceGrant boilerplate — drop a `referenceGrants.from-gateway-ns` map entry and the resource is generated.
- Per-workload route rules contributed automatically to the right merged route, with deterministic ordering.

**What it costs:**

- Five route templates plus two Ingress shapes (singleton + map) is a lot of surface. Tests cover each (`tests/httproute_test.yaml`, `tests/grpcroute_test.yaml`, `tests/tlsroute_test.yaml`, `tests/ingress_test.yaml`, `tests/referencegrant_test.yaml`).
- The "rules merge from per-workload shorthand" model needs a clear ordering contract. Implemented as: explicit `priority` first (ascending), then alphabetical by workload name. See [ADR 014](014-deterministic-ordering.md).
- A user can configure both `ingress` and `ingresses` (singleton + map) at the same time. The chart renders both — duplicates are the user's problem. This is an intentional simplification; a fail-fast check would over-constrain unusual but valid setups (singleton for legacy, map for new).
- Gateway API requires CRDs installed in the cluster. The chart assumes installs match the user's intent: if `httpRoute.enabled: true` is set without the CRD installed, `kubectl apply` fails with a clear message.

## Per-workload shorthand example

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: my-gateway
      namespace: gateway-system
  hostnames:
    - app.example.com

deployments:
  api:
    service:
      ports:
        http:
          port: 80
          targetPort: 8080
    httpRoute:
      enabled: true
      priority: 10
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /api
  web:
    service:
      ports:
        http:
          port: 80
          targetPort: 80
    httpRoute:
      enabled: true
      priority: 20
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
```

Renders one HTTPRoute with two merged rules: API first, web second. `serviceName` defaults to `<release-fullname>-api` / `-web`; `servicePort` defaults to the workload's `service.port`.

## Alternatives considered

- **Ingress only.** Rejected: closes the door on Gateway API migrations.
- **Gateway API only.** Rejected: many clusters still don't have a Gateway controller installed; Ingress remains the lowest-common-denominator routing primitive.
- **Per-workload Ingress, no singleton.** Rejected: the common case is one Ingress per release; making users pay multi-resource ceremony for the common case is a regression.
- **Render `parentRefs` / `hostnames` on every per-workload route.** Rejected: invites drift; one source of truth (singleton) and inheritance is cleaner.

## References

- `values.yaml` — the `ingress` / `ingresses` and Gateway API (`httpRoute` / `httpRoutes` / `grpcRoute` / `grpcRoutes` / `tlsRoute` / `tlsRoutes` / `referenceGrant` / `referenceGrants`) blocks.
- `templates/ingress.yaml`, `templates/httproute.yaml`, `templates/grpcroute.yaml`, `templates/tlsroute.yaml`, `templates/referencegrant.yaml`.
- Tests: `tests/ingress_test.yaml`, `tests/httproute_test.yaml`, `tests/grpcroute_test.yaml`, `tests/tlsroute_test.yaml`, `tests/referencegrant_test.yaml`.
- Related: [ADR 014](014-deterministic-ordering.md).
