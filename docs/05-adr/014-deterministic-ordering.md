# 014 — Deterministic ordering of map-iterated collections

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

The chart's choice to use maps instead of lists ([ADR 004](004-maps-over-lists.md)) means every collection iteration has to pick an order. Go maps in templates have an unspecified iteration order; without an explicit sort, the rendered output flips between renders and Argo CD / `helm diff` show meaningless churn.

For most fields, alphabetical ordering is sufficient. Two fields specifically aren't:

- **Service / container ports.** "http" should come first by convention — that's what most operators expect when they read a Service's `ports[]`. "metrics" should come last — it's the auxiliary observability port. Alphabetical would put `admin` before `http`.
- **Gateway API rule precedence.** Gateway API matches rules top-down; the order is part of the contract. We expose a `priority` field so users can express "this rule before that rule" without coupling to alphabetical key choice.

## Decision

Three rules, applied uniformly:

### Rule 1: Default — alphabetical sort by map key

Every map-iterating template uses `keys ... | sortAlpha` before `range`. This applies to:

- `deployments`, `statefulSets`, `jobGroups` (workload maps)
- `service.ports` (most positions; see Rule 2)
- `volumes`, `volumeMounts`, `configMaps`, `sidecars`
- `ingresses`, `httpRoutes`, `grpcRoutes`, `tlsRoutes`, `referenceGrants`
- `integrations.eso.secretStores`, `integrations.eso.externalSecrets`
- Tasks-mode `initContainers` inside a Job's `tasks` map

### Rule 2: Special-cased port ordering — http first, metrics last

For `service.ports` and per-container `ports`, the order is:

```
"http" (if present)  →  others alphabetically  →  "metrics" (if present)
```

Implemented in `templates/_helpers.tpl:uhc.orderedPortNames`. The metrics port auto-injected by `integrations.monitoring.defaults.exposeService` ([ADR 016](016-metrics-port-auto-exposure.md)) is also appended last.

Rationale: the first port in a Service's `ports[]` is the one that matters most — health probes, kubectl port-forward shorthand, default network-policy assumptions all point at it. Putting "http" first makes the common case consistent. Putting "metrics" last keeps observability ports out of the way of operational reading.

### Rule 3: Explicit `priority` overrides alphabetical for ordered semantics

For per-workload Gateway API route shorthand (`deployments.<w>.httpRoute.priority`, similarly grpc/tls), users can set an integer. Lower numbers come first in the merged route's `rules[]`. Ties broken alphabetically by workload name. Workloads without `priority` are sorted alphabetically among themselves (and the chart treats them as priority `+∞` when comparing with explicitly-prioritised entries).

## Consequences

**What this enables:**

- A `helm template` rerun on identical inputs produces byte-identical output. Argo CD / `helm diff` only show meaningful changes.
- Operators reading Service definitions can expect "http" first, "metrics" last — a predictable mental model across services.
- Gateway API rule precedence is explicit and stable across renders.

**What it costs:**

- Renaming a workload changes its alphabetical position. In Gateway API rule order this matters — `deployments.api` vs `deployments.zapi` change the order in the merged HTTPRoute. Mitigation: use `priority` to lock down rule order independently of key naming.
- Users wanting a non-standard port order (e.g. metrics first) cannot get it without renaming their port. The chart treats this as a feature.
- The `keys ... | sortAlpha` pattern is repeated across templates. Refactoring to a single helper is on the wishlist but the cost of inconsistency in the meantime is low.

## Worked examples

```yaml
deployments:
  api:
    service:
      ports:
        admin:   { port: 8081, targetPort: 8081 }
        http:    { port: 80,   targetPort: 8080 }
        metrics: { port: 9090, targetPort: 9090 }
        rpc:     { port: 9000, targetPort: 9000 }
```

Rendered Service `ports[]` order:
```text
http, admin, rpc, metrics
```

Gateway API rule merge:
```yaml
deployments:
  z-api: { httpRoute: { enabled: true, priority: 10, rules: [...] } }
  api:   { httpRoute: { enabled: true, priority: 20, rules: [...] } }
  web:   { httpRoute: { enabled: true,                  rules: [...] } }
```

Order in merged HTTPRoute `rules[]`: `z-api` (priority 10), `api` (priority 20), `web` (no priority, alphabetised among unprioritised — only one here, but if `home` also had no priority it would precede `web`).

## Alternatives considered

- **Pure alphabetical for ports too.** Rejected: violates the operational intuition that `http` is the "main" port.
- **Insertion order from `values.yaml`.** Rejected: not portable across YAML libraries; merging overlay values would break any guarantee.
- **Explicit `order` integer on every map entry.** Rejected: more knobs everywhere, and most users don't care.
- **Per-port `weight` field instead of fixed http/metrics rule.** Rejected: solves a problem that doesn't exist for the 99% case.

## References

- `templates/_helpers.tpl` — `uhc.orderedPortNames`
- `templates/service.yaml`, `templates/deployment.yaml`, `templates/statefulset.yaml` (ports rendering)
- `templates/httproute.yaml`, `templates/grpcroute.yaml`, `templates/tlsroute.yaml` (rule merge with priority)
- Tests: `tests/service_test.yaml`, `tests/fixtures/service-multiport.yaml`, `tests/fixtures/httproute-sort.yaml`
- Related: [ADR 002](002-multi-workload-keyed-maps.md), [ADR 004](004-maps-over-lists.md), [ADR 009](009-dual-networking-stack.md), [ADR 016](016-metrics-port-auto-exposure.md)
