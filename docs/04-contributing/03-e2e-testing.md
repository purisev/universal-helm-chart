# E2E testing

`helm-unittest` (see [`02-testing.md`](02-testing.md)) only proves the chart *renders* the YAML you expect — it never touches a real API server. This suite does: each job spins up a real [kind](https://kind.sigs.k8s.io/) cluster, installs the real controllers a feature depends on (Gateway API + agentgateway, KEDA, External Secrets Operator, cert-manager, Calico, Argo CD, Prometheus/VictoriaMetrics operators, …), installs the chart against it, and asserts on real, live behavior — an HTTP/gRPC/TLS request that actually gets routed, a pod that actually restarts, an autoscaler that actually scales — using [Chainsaw](https://kyverno.github.io/chainsaw/) as the test runner.

## It's label-gated, not run on every push

Standing up a dozen controllers per push would be slow and wasteful. `.github/workflows/e2e.yaml` only runs when:

- the PR carries the `e2e` label — runs every job, or
- the PR carries an `e2e:<job>` label — runs just that job, or
- the workflow is triggered manually (`workflow_dispatch`) — runs every job.

A `gate` job reads the PR's labels and sets one boolean output per job; every `e2e-*` job is `if: needs.gate.outputs.<job> == 'true'`. Label a PR with the narrowest `e2e:<job>` that covers what you changed — not the blanket `e2e` label — so CI time stays proportional to the change.

## The jobs

| Job | Label | Covers |
|-----|-------|--------|
| `e2e-core-workloads` | `e2e:core-workloads` | Deployment rollout, StatefulSet (headless DNS, independent Service), Service routing, ConfigMap automount, envFrom, PodDisruptionBudget eviction, RBAC, container `resizePolicy` |
| `e2e-jobs` | `e2e:jobs` | `jobGroups` Job (basic/indexed/suspend-resume/`podFailurePolicy`), CronJob manual trigger |
| `e2e-autoscaling` | `e2e:autoscaling` | HPA (structural), KEDA (real cron-driven scale-out and scale-to-zero), VPA (recommendation) |
| `e2e-gateway-ingress` | `e2e:gateway-ingress` | Ingress (real HTTP + real TLS termination), HTTPRoute, GRPCRoute (real gRPC call), TLSRoute (real TLS passthrough by SNI), ReferenceGrant (real cross-namespace deny/allow) |
| `e2e-secrets-config` | `e2e:secrets-config` | ESO SecretStore/ClusterSecretStore against a real single-replica Vault (Bank-Vaults operator), Stakater Reloader on ConfigMap, StatefulSet, and ExternalSecret changes |
| `e2e-observability` | `e2e:observability` | ServiceMonitor/PodMonitor materialization and real scraping, Prometheus and VictoriaMetrics flavors |
| `e2e-network-policy` | `e2e:network-policy` | NetworkPolicy ingress and egress enforcement (Calico; kind's default CNI doesn't enforce NetworkPolicy at all) |
| `e2e-argocd` | `e2e:argocd` | Argo CD Application sync/health, resync idempotency, Image Updater tag detection, PreSync hook ordering |

Each job's cluster only carries the controllers that job's scenarios need — `e2e-secrets-config` doesn't install Gateway API CRDs, `e2e-gateway-ingress` doesn't install Vault, and so on.

## Layout

```
test/e2e/
  kind/<job>.yaml            — kind cluster config (some jobs share test/e2e/kind/default.yaml)
  values/<job>.yaml          — scenario-scoped values (not the values.yaml.example kitchen sink)
  fixtures/                  — raw manifests the workflow applies before/alongside the chart (Gateway, RBAC, CRs, …)
  scripts/                   — small helpers a chainsaw script/command step shells out to
  chainsaw/<job>/            — one directory per test scenario, one chainsaw-test.yaml each
  chainsaw/<job>-config.yaml — chainsaw Configuration for that job (default namespace, timeouts)
```

A scenario directory's `chainsaw-test.yaml` is one or more `steps`, each an `apply`/`assert`/`script` sequence. Prefer `script` with a poll loop over a bare `assert` whenever the thing being checked can lag behind an object's `status` conditions (a controller's dataplane catching up to a spec change, a cron window closing, propagating an external system's state) — several tests in this suite were flaky before switching to that pattern.

## Running a job locally

```bash
kind create cluster --config test/e2e/kind/<job>.yaml
# install that job's prerequisite controllers — see the corresponding
# steps in .github/workflows/e2e.yaml for the exact commands/versions
helm upgrade --install e2e . -n <namespace> -f test/e2e/values/<job>.yaml --wait --timeout 3m
chainsaw test test/e2e/chainsaw/<job> --config test/e2e/chainsaw/<job>-config.yaml
```

The workflow file is the source of truth for each job's exact controller-install steps (versions, Helm repos, wait conditions) — copy them from there rather than guessing, since several depend on version-specific quirks (e.g. cert-manager's webhook can report `Available` before its CA bundle has actually propagated).

## Adding a scenario

1. Pick the job whose cluster already has what the scenario needs, or start a new job if it needs a controller none of the existing ones install.
2. Add a `test/e2e/chainsaw/<job>/<scenario>/chainsaw-test.yaml`. Extend `test/e2e/values/<job>.yaml` (and `fixtures/` if the scenario needs a raw manifest the chart doesn't render, like a Gateway or a CR) rather than adding a new values file, unless the scenario needs a materially different install.
3. Assert on real, observable behavior, not just object shape — a request that gets routed, a pod that restarts, a value that changes — the same bar the existing scenarios hold themselves to. Object-shape-only assertions belong in `helm-unittest`, which is far cheaper to run.
4. Label the PR `e2e:<job>` and confirm the job goes green before merging.
