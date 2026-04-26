# 007 — Autoscaler mutual exclusion (HPA / KEDA / VPA)

- **Status:** Accepted
- **Date:** 2025-04-25

## Context

Three different controllers can mutate a workload's runtime sizing:

- **HPA** (`autoscaling/v2` HorizontalPodAutoscaler) — scales `spec.replicas` based on CPU / memory / custom metrics.
- **KEDA** (`keda.sh` `ScaledObject`) — also scales `spec.replicas`, driven by event sources (Kafka lag, queue depth, cron, …). KEDA creates an HPA under the covers.
- **VPA** (`autoscaling.k8s.io` VerticalPodAutoscaler) — adjusts `containers[].resources.requests` (and optionally limits) based on observed usage.

The chart exposes per-workload knobs for all three. Without explicit constraints, a values file could enable both HPA and KEDA on the same Deployment — two HPAs (the user's plus KEDA's) fight over `spec.replicas` and the result is undefined oscillation. Less catastrophically, a Deployment with HPA enabled but `spec.replicas` set to a fixed number creates a one-shot conflict on every Helm apply: HPA scales away from the value, the next `helm upgrade` writes it back.

## Decision

- **HPA and KEDA are mutually exclusive per workload.** The chart enforces this at template render: enabling KEDA's `ScaledObject` for a workload that also has HPA enabled is a `fail`. Users pick one.
- **VPA is orthogonal** to both. VPA touches `resources.requests`; HPA / KEDA touch `replicas`. They can co-exist on the same workload, though running VPA in `Auto` mode together with HPA on CPU/memory targets is rarely a good idea.
- **`spec.replicas` is omitted from the rendered workload when HPA or KEDA is enabled.** This prevents the per-deploy fight described above. Without an autoscaler, the chart writes the user-supplied (or default) replica count.

The check lives at `templates/hpa.yaml:7–8` (HPA suppression when KEDA is on) and at the Deployment / StatefulSet templates' `spec.replicas` rendering (omitted when an HPA-class scaler is active).

## Consequences

**What this enables:**

- A single values switch decides "auto-scale on metrics" (`hpa.enabled: true`) vs "auto-scale on events" (`keda.enabled: true`). Users cannot accidentally turn on both.
- VPA can be enabled on every workload to recommend (or in `Recreate` mode, set) right-sized resource requests, regardless of horizontal scaling.
- A redeploy with HPA on does not bounce the replica count — Helm doesn't write `replicas`, so HPA's last decision sticks.

**What it costs:**

- Users wanting "manual replicas overridden by HPA only on traffic spikes" must opt out of the chart's "HPA on → no replicas in spec" behaviour — they would set `replicaCount` for the very first apply, then turn HPA on. The chart does not support a hybrid mode.
- The `fail` on HPA + KEDA simultaneously is loud. The error message names both keys so users can fix it without reading the source.

## Defaults

All three are off by default. This is per-workload too — `hpa.enabled`, `keda.enabled`, `verticalPodAutoscaler.enabled` each default to `false` at root and may be overridden per `deployments.<name>` or `statefulSets.<name>`.

## Alternatives considered

- **Allow HPA + KEDA together.** Rejected: KEDA already manages an HPA; a user-supplied second HPA is double scaling.
- **Choose for the user (e.g. KEDA wins if both are on).** Rejected: silent precedence is harder to debug than a fail.
- **Treat VPA as also mutually exclusive with HPA.** Rejected: too restrictive; the well-known caveat (don't VPA-manage CPU when HPA scales on CPU) is documentable. In the most common case (VPA `updateMode: Initial` for memory + HPA on CPU) the combination is safe and useful.

## References

- `values.yaml:1069–1083` — VPA defaults
- `templates/hpa.yaml`, `templates/scaledobject.yaml`, `templates/verticalpodautoscaler.yaml`
- `templates/deployment.yaml:19–23`, `templates/statefulset.yaml` (replicas omission when scaling enabled)
- `tests/deployment_test.yaml` — replica-omission cases; `tests/scaledobject_test.yaml` — KEDA exclusion check
