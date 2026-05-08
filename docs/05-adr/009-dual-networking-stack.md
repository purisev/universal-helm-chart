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

**HTTPRoute rule-level fields.** Each rule in `httpRoute.rules` (root, per-workload, or plural-map) supports four optional field groups from the Gateway API spec: `name` (identifies the rule in status and traces), `timeouts` (`request` and `backendRequest` as Gateway API Duration strings — [GEP-2257](https://gateway-api.sigs.k8s.io/geps/gep-2257/)), `retry` (`attempts`, `codes` status-code list 400–599, `backoff`), and `sessionPersistence` (`sessionName`, `type` (`Cookie`/`Header`), `absoluteTimeout`, `idleTimeout`, `cookieConfig.lifetimeType`). All four are independently optional and are omitted from the rendered manifest when not set. Channel/version requirements: `name` needs Gateway API v1.4+ Standard or v1.2+ Experimental CRDs; `timeouts` is Standard since v1.2; `retry` and `sessionPersistence` are **Experimental only** as of Gateway API v1.5.1. The chart fails fast when a field is set but the cluster's installed CRD channel does not support it (detection skipped during offline `helm template`).

**HTTPRoute rule schema strictness.** Each entry in `httpRoute.rules` (and the equivalent under `httpRoutes.<n>.rules` and per-workload route maps) is validated against a strict schema (`additionalProperties: false`) listing only the supported fields: `name`, `matches`, `filters`, `backendRefs`, `serviceName`, `servicePort`, `timeouts`, `retry`, `sessionPersistence`. Unknown keys — typos, deprecated fields, or Gateway API fields not yet wired into the chart — now fail at `helm template` time instead of being silently dropped. This is a behaviour change relative to the previous loose `type: array` validation on `httpRoute.rules`; if you depend on a Gateway API HTTPRouteRule field not in the list above, file an issue or submit a PR.

**GRPCRoute rule-level fields.** Each rule in `grpcRoute.rules` (root, per-workload, or plural-map) supports `name` (Gateway API SectionName, identifies the rule in status and traces) and `sessionPersistence` (`sessionName`, `type` (`Cookie`/`Header`), `absoluteTimeout`, `idleTimeout`, `cookieConfig.lifetimeType`) on top of the existing `matches`/`filters`/`backendRefs`. Both are independently optional. The Gateway API spec **does not define `timeouts` or `retry` on GRPCRouteRule** — those are HTTPRoute-only — so the chart does not surface them. Channel/version requirements: `name` needs Gateway API v1.4+ Standard or v1.2+ Experimental CRDs; `sessionPersistence` is **Experimental only** as of Gateway API v1.5.1. The chart fails fast at template time when a field is set but the cluster's installed CRD channel does not support it (detection skipped during offline `helm template`). The same strict per-rule schema (`additionalProperties: false`) now applies to GRPCRoute rules — unknown keys fail fast.

**TLSRoute rule-level fields.** Each rule in `tlsRoute.rules` (root, per-workload, or plural-map) supports `name` (Gateway API SectionName, identifies the rule) on top of `backendRefs`. The Gateway API spec defines **only `name` and `backendRefs`** on TLSRouteRule — TLS is L4 passthrough, so `matches`, `filters`, `timeouts`, `retry`, and `sessionPersistence` are not part of the type and are not surfaced by the chart. TLSRoute itself is Experimental-only (`gateway.networking.k8s.io/v1alpha2`), so any use of TLSRoute already presupposes Experimental CRDs — `name` adds no further per-field channel requirement. The same strict per-rule schema (`additionalProperties: false`) now applies to TLSRoute rules.

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
        - name: api-traffic
          matches:
            - path:
                type: PathPrefix
                value: /api
          timeouts:
            request: 30s
            backendRequest: 10s
          retry:
            attempts: 3
            codes: [503, 504]
            backoff: 1s
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

Renders one HTTPRoute with two merged rules: API first (with name, timeouts, retry), web second (minimal catch-all). `serviceName` defaults to `<release-fullname>-api` / `-web`; `servicePort` defaults to the workload's `service.port`.

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
