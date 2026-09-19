# Local development

## Prerequisites

- Helm **3.14+**
- helm-unittest plugin:

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest --verify=false
```

That's it.

## Clone and verify

```bash
git clone https://github.com/purisev/universal-helm-chart.git
cd universal-helm-chart
helm lint .
helm unittest .
```

Sub-minute end-to-end. If those two commands pass, your environment is ready.

## Dev loop

Three commands cover 99% of the work:

| Command | When to run |
|---------|-------------|
| `helm template my-app .` | After any template or values change — fastest visual check of the rendered manifests. |
| `helm lint .` | Before pushing — catches schema mismatches and shape problems CI will also reject. |
| `helm unittest .` | Before pushing — catches behavioural regressions. Add a new test case in the matching `tests/<template>_test.yaml` whenever you add a feature. |
| `bash .github/scripts/check-version-pins.sh` | After touching `Chart.yaml` or any install snippet in `docs/` — holds every documented version to the one in `Chart.yaml`. |
| `bash .github/scripts/check-examples.sh` | After touching the values shape, the schema or anything under `docs/02-examples/` — renders every example, including the values inlined in its Argo CD and Flux manifests, and checks each Ingress backend against the Services the same values render. Needs `yq`. |

To render a single template against custom values:

```bash
helm template my-app . -s templates/deployment.yaml -f my-values.yaml
```

## Common pitfalls

- **Changed the values shape?** Update [`values.schema.json`](https://github.com/purisev/universal-helm-chart/blob/main/values.schema.json) in the same commit. Schema and `values.yaml` drift is the most common reviewer comment.
- **Added a field?** Add at least one assertion in `tests/<template>_test.yaml`. Coverage prevents silent regressions on future refactors.
- **Bumped the chart version?** Every Argo CD `targetRevision`, Flux `tag`, `helm install --version` and schema URL under `docs/` names it too. `check-version-pins.sh` lists the ones you missed; CI runs it on every run, the e2e suites wait on it, and the branch preview build will not publish while it is red.
- **Changed an example?** Each example carries the same values three times: `values.yaml`, the Argo CD `Application`, and the Flux `HelmRelease`. Change one and the other two go stale. `check-examples.sh` renders all three and fails on the ones that no longer install — or that name a Service nothing renders.
- **Writing fixtures or example values?** Use **block-style** YAML throughout — multi-line indented maps and lists, never the inline curly-brace / square-bracket form. The chart docs are authored as reference material; keeping the style consistent matters.
