# 004 — Maps over lists as the default collection shape

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

Many Kubernetes resource specs are lists where each item carries a name: `containers`, `volumes`, `volumeMounts`, `ports`, `env`, `imagePullSecrets`, Ingress hosts, Service ports. Helm chart values can mirror that list shape directly, or transpose it into a map keyed by the natural-key field. The choice shapes everything users do downstream:

- **Overlay merging.** Helm merges values from `-f` overlays. Maps merge per key; lists are replaced wholesale. Lists therefore force the overlay to redeclare every entry.
- **Duplicate prevention.** YAML maps reject duplicate keys at parse time; lists let you have two `containers[].name: foo` and the kubelet rejects the pod at *runtime*.
- **Targeted disabling / overriding.** A map gives you `entry.<name>.enabled: false` for free; with a list you have to filter it during template render.
- **Diff stability.** A reordered list looks like a meaningful diff to Argo CD; a reordered map round-trips identically because we sort it.

The 2.0.0 refactor (commit `56a1a79`) finished a multi-PR effort to push as many list-shaped values as possible into maps.

## Decision

**Default to maps.** A `values.yaml` collection becomes a map keyed by its natural unique field whenever such a field exists. The rendered YAML uses the **map key** as the resource field's name (volume name, port name, host name, container name, secret name, etc.) — users do not repeat the name inside the value.

A collection stays as a **list** only when one of these is true:

1. **No natural key.** Examples: `tolerations` (matched by combinations of fields, not name), `rbac.rules` (a tuple of `apiGroups + resources + verbs`), Gateway API `rules` (an ordered list of match-and-forward records), `ingress.hosts.<host>.paths` (path order matters in some controllers).
2. **Order is part of the contract.** Examples: pod `initContainers` in tasks-mode `jobGroups` (we sort by name to make order *deterministic*, but users still see a list-like ordering by alphabetised key); HTTP route precedence (handled with an explicit `priority` field — see [ADR 014](014-deterministic-ordering.md)).
3. **Duplicates are legitimate.** Example: `dataFrom` in External Secrets, where the same `remoteKey` can appear with different conversion strategies.
4. **A list of plain strings reads better than a one-key-per-string map.** Examples: `imagePullSecrets`, `envSecrets`, `envConfigMaps`, `priorityClassName` lists, `hostAliases.hostnames`. The chart wraps each entry into the right object shape (`{name: <s>}` for image pull secrets, `{secretRef: {name: <s>}}` for envFrom).

When a map is used, the chart **always** iterates with `keys ... | sortAlpha` so output order is deterministic regardless of `values.yaml` author's keystroke order. Special cases (port name ordering, init container ordering) live in [ADR 014](014-deterministic-ordering.md).

## Consequences

**What this enables:**

- Overlay values can target one entry without rewriting the rest:
  ```yaml
  # base.yaml
  deployments.api.service.ports:
    http: { port: 80, targetPort: 8080 }
    metrics: { port: 9090, targetPort: 9090 }
  # prod-overlay.yaml — bumps the metrics port only
  deployments.api.service.ports.metrics.port: 9091
  ```
- Duplicate volume names, port names and the like are caught by the YAML parser before the chart even runs.
- Per-entry disabling reads naturally: `configMaps.app-config.enabled: false`.
- Helper code is consistent: every map-iterating loop reuses the same `keys ... | sortAlpha` pattern.

**What it costs:**

- Migrating a list to a map is a breaking change to the `values.yaml` API. The 2.0.0 release line absorbs this cost; future migrations will need ADRs of their own.
- Map keys collide with reserved identifier rules: a port name must be ≤15 chars (RFC 6335), a host must be a valid DNS name. `values.schema.json` enforces these at chart-install time. See [ADR 013](013-schema-driven-validation.md).
- Some users prefer the list shape because it visually resembles raw Kubernetes manifests. We accept the small re-learning cost in exchange for the merge / dedup / dedupe properties above.

## Migration philosophy (commit `56a1a79`)

The pre-2.0.0 chart had a mix of list and map shapes for similar concepts. The 2.0.0 line landed three rounds of consolidation:

- `bf668bc` — `monitoring` providers refactored to a defaults-driven matrix (incidental side-effect: trimmed lists in scrape config).
- `43873b1` — `integrations` namespace introduction (incidental side-effect: ecosystem knobs that used to be top-level lists became maps under `integrations.*`).
- `56a1a79` — explicit collapse of remaining lists into maps where a natural key existed: `volumes`, `volumeMounts`, `service.ports`, `ports`, `ingress.hosts`, `ingress.tls`, `httpRoutes`, `referenceGrants`, `configMaps`, `sidecars`. Lists kept: `imagePullSecrets`, `envSecrets`, `envConfigMaps` (now lists of plain strings), Gateway API `rules`, `rbac.rules`, `tolerations`, `hostAliases`, ESO `dataFrom`.

## Alternatives considered

- **Keep everything as a list (mirror Kubernetes API verbatim).** Rejected: gives up overlay-merge wins, duplicate prevention, and per-entry disabling.
- **Keep everything as a map (no lists at all).** Rejected: the four exceptions above are real — a deduplicated map representation of `tolerations` or Gateway API `rules` either misrepresents the upstream type or invents synthetic keys.
- **Custom DSL on top of values.** Rejected: more to learn; less inspectable.

## References

- Commits: `bf668bc`, `43873b1`, `56a1a79`
- `values.yaml` throughout — every map-shaped field is documented with a "Map key → …" comment naming the Kubernetes field it lands in.
- Related: [ADR 002](002-multi-workload-keyed-maps.md), [ADR 014](014-deterministic-ordering.md), [ADR 013](013-schema-driven-validation.md)
