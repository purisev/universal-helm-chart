# Releasing

The chart is published to GHCR as an OCI artifact (`oci://ghcr.io/purisev/universal-helm-chart`). Two CI workflows under [`.github/workflows/`](../../.github/workflows/) handle the publishing automatically.

## Cutting a release (tagged build)

1. **Check `Chart.yaml`.** The `version` field is pinned to the in-flight release line and must already match the version you want to publish — don't bump per-PR.
2. **Tag and push** from the matching release branch:

   ```bash
   git checkout release-2.0.0
   git tag v2.0.0
   git push origin v2.0.0
   ```

3. **CI takes over.** [`release.yaml`](../../.github/workflows/release.yaml) runs on `v*` tags: it lints, runs the unittest suite, packages the chart and pushes the artifact to `oci://ghcr.io/purisev`.
4. **Verify the artifact:**

   ```bash
   helm pull oci://ghcr.io/purisev/universal-helm-chart --version 2.0.0
   ```

## Branch builds (PR previews)

[`ci.yaml`](../../.github/workflows/ci.yaml) also publishes a preview artifact for every non-draft PR, tagged `<chart-version>-<branch-slug>` — for example `2.0.0-feat-xyz`. Reviewers can pull it directly without cloning:

```bash
helm template demo oci://ghcr.io/purisev/universal-helm-chart --version 2.0.0-feat-xyz -f my-values.yaml
```

## What gets published

The OCI artifact contains only what chart consumers need: `Chart.yaml`, `templates/`, `values.yaml`, `values.schema.json`, `README.md`, `LICENSE`, `NOTICE`. Everything else (`docs/`, `tests/`, `.github/`, `.claude/`) is excluded via [`.helmignore`](../../.helmignore).
