# 04 — Gateway API with cross-namespace ReferenceGrant

Two Deployments (`api`, `web`) routed by a singleton HTTPRoute. The Gateway lives in a different namespace (`gateway-system`) — a `ReferenceGrant` permits the cross-namespace backend reference.

## What this shows

- Singleton `httpRoute` declaration with `parentRefs` pointing to a Gateway in `gateway-system`.
- **Per-workload route shorthand**: each workload contributes rules into the merged HTTPRoute via `deployments.<n>.httpRoute.rules`. Order is controlled by `priority` (lower wins; ties alphabetical).
- `serviceName` and `servicePort` default to the workload's own Service — no manual cross-reference.
- `referenceGrant` allows the gateway-system namespace to reference Services in this release's namespace. Without it, Gateway API rejects the cross-namespace backend ref.
- Path-based routing: `/api/*` → `api` workload, everything else → `web` workload.
- **Rule-level `name`**: optional string (lowercase RFC 1123 label) identifying a rule in Gateway API status, traces, and access logs. Requires Gateway API **v1.4+ Standard** or **v1.2+ Experimental** CRDs.
- **Rule-level `timeouts`**: `request` caps the full round-trip budget; `backendRequest` caps backend processing time (must be ≤ `request`). Both accept Gateway API Duration strings (`30s`, `1h30m`, `100ms`). Standard since Gateway API v1.2.
- **Rule-level `retry`**: `attempts` sets the attempt limit; `codes` lists HTTP status codes 400–599 that trigger a retry (implementations MUST support 500/502/503/504); `backoff` sets the minimum delay between attempts. **Requires Gateway API Experimental channel CRDs** — Standard CRDs reject the field.

## Delta from `02-web-app-ingress`

| Changed | What and why |
|---------|--------------|
| Ingress → HTTPRoute | Modern Gateway API instead of legacy Ingress. Same external behaviour, more expressive routing. |
| Per-workload routes | The route is split per backend — each workload owns its match rules — and merged into one resource. |
| `referenceGrant` block | Required for cross-namespace Service references in Gateway API. |
| Multiple workloads | Two Deployments serving different paths under one host. |
| Removed cert-manager annotation | TLS is handled at the Gateway listener level, outside this chart. |
| `name`, `timeouts`, `retry` on `api` rule | Shows rule identification, timeout budgets, and retry policy — absent from the `web` catch-all to contrast optional vs. omitted. |

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

- Gateway API CRDs (`gateway.networking.k8s.io`) installed.
- A Gateway named `external` running in the `gateway-system` namespace, with a listener (e.g. `https`) accepting routes from this namespace's selector.
- A Gateway controller compatible with Gateway API v1 (Cilium, Envoy Gateway, Istio, Traefik, Kong).

## Related ADRs

- [ADR 009 — Dual networking stack](../../05-adr/009-dual-networking-stack.md)
- [ADR 014 — Deterministic ordering](../../05-adr/014-deterministic-ordering.md) (rule ordering via `priority`)
