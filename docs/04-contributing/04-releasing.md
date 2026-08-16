# Releasing

The chart is published to GHCR as an OCI artifact under the maintainer's namespace (`oci://ghcr.io/purisev/universal-helm-chart` for this repo; `${{ github.repository_owner }}` for forks — see [Forks](#forks) below). Two CI workflows under [`.github/workflows/`](../../.github/workflows/) handle the publishing automatically.

## Cutting a release (tagged build)

1. **Check `Chart.yaml`.** The `version` field is pinned to the in-flight release line and must already match the version you want to publish — don't bump per-PR.
2. **Tag and push** from the matching release branch:

   ```bash
   git checkout release-3.0.0
   git tag v3.0.0
   git push origin v3.0.0
   ```

3. **CI takes over.** [`release.yaml`](../../.github/workflows/release.yaml) runs on `v*` tags: it lints, runs the unittest suite, packages the chart, pushes the artifact to `oci://ghcr.io/<your-github-namespace>` (the workflow resolves your namespace from `${{ github.repository_owner }}`), and signs it keylessly via [Sigstore/cosign](https://docs.sigstore.dev/) — no key management, the signature is tied to this repo's GitHub Actions OIDC identity.
4. **Verify the artifact:**

   ```bash
   helm pull oci://ghcr.io/purisev/universal-helm-chart --version 3.0.0
   ```

5. **Verify the signature** (optional, proves the artifact was actually built by this repo's `release.yaml` and not pushed by hand or from a fork):

   ```bash
   cosign verify \
     --certificate-identity-regexp "^https://github.com/purisev/universal-helm-chart/" \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
     ghcr.io/purisev/universal-helm-chart:3.0.0
   ```

## Branch builds (PR previews)

[`ci.yaml`](../../.github/workflows/ci.yaml) can also publish a preview artifact, tagged `<chart-version>-<branch-slug>` — for example `3.0.0-feat-xyz`. It's gated behind the `publish-preview` label (not automatic on every PR) and only runs once linting/tests have actually passed. Apply the label to a non-draft, non-fork PR to trigger it. Reviewers can then pull it directly without cloning:

```bash
helm template demo oci://ghcr.io/purisev/universal-helm-chart --version 3.0.0-feat-xyz -f my-values.yaml
```

## What gets published

The OCI artifact contains only what chart consumers need: `Chart.yaml`, `templates/`, `values.yaml`, `values.schema.json`, `README.md`, `LICENSE`, `NOTICE`, `SECURITY.md`. Everything else (`docs/`, `tests/`, `.github/`, `.claude/`) is excluded via [`.helmignore`](../../.helmignore).

## Forks

Both workflows resolve the GHCR namespace from `${{ github.repository_owner }}`, so a fork publishes to `oci://ghcr.io/<your-github-user>/universal-helm-chart` automatically — no workflow edits required. Tag a release on your fork's `release-<X.Y.Z>` branch the same way and `release.yaml` runs against your own GHCR namespace using your repo's `GITHUB_TOKEN`.
